.pragma library

// Ported from Shakespeare's ShakespeareCore (StatsEngine, Badges, FunFacts).
// Everything here is derived from the per-day counters keybomyd writes; nothing is stored.

var STREAK_THRESHOLD = 50
var KEYS_PER_WORD = 5
var HAMLET_WORDS = 30000
var WORDS_PER_PAGE = 250
var KEY_TRAVEL_MM = 1.0  // approximate travel of one press on a laptop keyboard, as in Shakespeare

// Word counts for the plays are approximate, from commonly cited figures.
var BADGES = [
  { id: "couplet", name: "Couplet", words: 20, blurb: "Two lines, one rhyme." },
  { id: "sonnet", name: "Sonnet", words: 120, blurb: "Fourteen lines and a volta." },
  { id: "soliloquy", name: "Soliloquy", words: 260, blurb: "To type, or not to type." },
  { id: "scene", name: "Scene", words: 2000, blurb: "Exit, pursued by a bear." },
  { id: "act", name: "Act", words: 6000, blurb: "Curtain up on act one." },
  { id: "comedy", name: "Comedy of Errors", words: 14000, blurb: "Shakespeare's shortest play." },
  { id: "macbeth", name: "Macbeth", words: 18000, blurb: "The Scottish play. We said it." },
  { id: "hamlet", name: "Hamlet", words: 30000, blurb: "Shakespeare's longest play." },
  { id: "tenhamlets", name: "Ten Hamlets", words: 300000, blurb: "Something is rotten in your keyboard." },
  { id: "complete", name: "Complete Works", words: 884000, blurb: "The whole First Folio, in one month." }
]

// Heights and lengths are approximate, from commonly cited figures.
var LANDMARKS = [
  { name: "the Tower of London", metres: 27 },
  { name: "the Leaning Tower of Pisa", metres: 56 },
  { name: "Big Ben", metres: 96 },
  { name: "the Eiffel Tower", metres: 330 },
  { name: "the Burj Khalifa", metres: 828 },
  { name: "the top of Mount Everest", metres: 8849 },
  { name: "the bottom of the Mariana Trench", metres: 10935 },
  { name: "the edge of space", metres: 100000 },
  { name: "the length of the Great Wall of China", metres: 21196000 }
]

function pad(n) { return n < 10 ? "0" + n : "" + n }

function dayKey(date) {
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function dateFromKey(key) {
  var p = key.split("-")
  return new Date(+p[0], +p[1] - 1, +p[2], 12)
}

function addDays(date, n) {
  var d = new Date(date.getFullYear(), date.getMonth(), date.getDate() + n, 12)
  return d
}

// stats.json is saved once a minute; live.json carries today's latest counters.
function merge(stats, live) {
  var days = {}
  var source = stats && stats.days ? stats.days : {}
  for (var key in source) days[key] = source[key]
  if (live && live.date && live.day) days[live.date] = live.day
  return days
}

function keysOn(days, date) {
  var day = days[dayKey(date)]
  return day ? (day.keys || 0) : 0
}

// The last n days ending today, oldest first.
function lastDays(days, n, now) {
  var out = []
  for (var offset = n - 1; offset >= 0; offset--) {
    var date = addDays(now, -offset)
    out.push({ date: date, keys: keysOn(days, date) })
  }
  return out
}

// Consecutive days with at least STREAK_THRESHOLD keys. A quiet today doesn't
// break the streak, since the day isn't over yet.
function streak(days, now) {
  var day = addDays(now, 0)
  if (keysOn(days, day) < STREAK_THRESHOLD) day = addDays(day, -1)
  var count = 0
  var limit = Object.keys(days).length
  while (keysOn(days, day) >= STREAK_THRESHOLD && count <= limit) {
    count++
    day = addDays(day, -1)
  }
  return count
}

function busiestDay(days) {
  var best = null
  var keys = Object.keys(days).sort()
  for (var i = 0; i < keys.length; i++) {
    var k = days[keys[i]].keys || 0
    if (k > (best ? best.keys : 0)) best = { key: keys[i], keys: k }
  }
  return best ? { date: dateFromKey(best.key), keys: best.keys } : null
}

function summary(days) {
  var result = { keys: 0, textKeys: 0, bestWPM: 0, busiestHour: -1 }
  var hours = []
  for (var h = 0; h < 24; h++) hours.push(0)
  for (var key in days) {
    var day = days[key]
    result.keys += day.keys || 0
    result.textKeys += day.textKeys || 0
    result.bestWPM = Math.max(result.bestWPM, day.bestWPM || 0)
    for (h = 0; h < 24; h++) hours[h] += (day.hours && day.hours[h]) || 0
  }
  var peak = Math.max.apply(null, hours)
  if (peak > 0) result.busiestHour = hours.indexOf(peak)
  return result
}

function totalWords(days) {
  return Math.floor(summary(days).textKeys / KEYS_PER_WORD)
}

// ------------------------------------------------------------------ badges

function monthKey(date) { return date.getFullYear() + "-" + pad(date.getMonth() + 1) }

function monthWords(days, now) {
  var month = monthKey(now)
  var keys = 0
  for (var key in days) if (key.indexOf(month) === 0) keys += days[key].textKeys || 0
  return Math.floor(keys / KEYS_PER_WORD)
}

// Every badge, with this month's progress and the lifetime collection.
function badgeStatuses(days, now) {
  var current = monthKey(now)
  var timesEarned = {}, firstEarned = {}, earnedThisMonth = {}
  var month = "", cumulative = 0, next = 0
  var keys = Object.keys(days).sort()  // "yyyy-MM-dd" sorts chronologically
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var thisMonth = key.substring(0, 7)
    if (thisMonth !== month) { month = thisMonth; cumulative = 0; next = 0 }
    cumulative += days[key].textKeys || 0
    var words = Math.floor(cumulative / KEYS_PER_WORD)
    while (next < BADGES.length && words >= BADGES[next].words) {
      var id = BADGES[next].id
      timesEarned[id] = (timesEarned[id] || 0) + 1
      if (!firstEarned[id]) firstEarned[id] = dateFromKey(key)
      if (month === current) earnedThisMonth[id] = dateFromKey(key)
      next++
    }
  }
  return BADGES.map(function(b) {
    return {
      badge: b,
      earnedThisMonthOn: earnedThisMonth[b.id] || null,
      timesEarned: timesEarned[b.id] || 0,
      firstEarned: firstEarned[b.id] || null
    }
  })
}

// The next badge to earn this month and progress (0..1) toward it, or null.
function nextBadge(days, now) {
  var words = monthWords(days, now)
  var badge = null, previous = 0
  for (var i = 0; i < BADGES.length; i++) {
    if (words < BADGES[i].words) { badge = BADGES[i]; break }
    previous = BADGES[i].words
  }
  if (!badge) return null
  var span = badge.words - previous
  return { badge: badge, progress: span > 0 ? (words - previous) / span : 0, words: words }
}

// ------------------------------------------------------------------ fun facts

function travelMetres(keys) { return keys * KEY_TRAVEL_MM / 1000 }

function hamlets(textKeys) { return textKeys / KEYS_PER_WORD / HAMLET_WORDS }

function novelPages(words) { return words / WORDS_PER_PAGE }

function hourLabel(hour, twelveHour) {
  if (hour < 0) return "–"
  if (!twelveHour) return pad(hour) + ":00"
  var h = hour % 12 === 0 ? 12 : hour % 12
  return h + " " + (hour < 12 ? "AM" : "PM")
}

function formatNumber(n) {
  return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

// Compact form for the bar: 950, 12.4k, 1.2M.
function compact(n) {
  if (n < 1000) return "" + n
  if (n < 1000000) return (n < 10000 ? (n / 1000).toFixed(1) : Math.floor(n / 1000)) + "k"
  return (n / 1000000).toFixed(1) + "M"
}

function distanceLabel(metres) {
  if (metres >= 100000) return formatNumber(metres / 1000) + " km"
  if (metres >= 1000) return (metres / 1000).toFixed(2) + " km"
  return metres.toFixed(1) + " m"
}

// Stays on one landmark until you reach 100% of it, then moves to the next.
function travelFact(metres) {
  var travelled = distanceLabel(metres)
  for (var i = 0; i < LANDMARKS.length; i++) {
    if (metres < LANDMARKS[i].metres) {
      var percent = Math.floor(metres / LANDMARKS[i].metres * 100)
      return "Your keys have travelled " + travelled + ", " + percent + "% of the way to " + LANDMARKS[i].name + "."
    }
  }
  var last = LANDMARKS[LANDMARKS.length - 1]
  return "Your keys have travelled " + travelled + ", " + (metres / last.metres).toFixed(1) + "× " + last.name + "."
}
