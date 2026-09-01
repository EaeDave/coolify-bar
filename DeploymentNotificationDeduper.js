.pragma library

// All bar widgets share this module in the shell's QML engine. One Coolify
// widget is mounted per monitor, so this prevents each instance from emitting
// the same deployment event.
var claims = ({})
var claimLifetimeMs = 24 * 60 * 60 * 1000

function eventKey(sourceId, deploymentId, statusKind) {
  return JSON.stringify([
    String(sourceId || ""),
    String(deploymentId || ""),
    String(statusKind || "")
  ])
}

function prune(now) {
  for (var key in claims) {
    if (now - Number(claims[key]) > claimLifetimeMs)
      delete claims[key]
  }
}

function claim(sourceId, deploymentId, statusKind) {
  var key = eventKey(sourceId, deploymentId, statusKind)
  var now = Date.now()
  prune(now)
  if (claims[key] !== undefined)
    return false
  claims[key] = now
  return true
}

function release(sourceId, deploymentId, statusKind) {
  delete claims[eventKey(sourceId, deploymentId, statusKind)]
}
