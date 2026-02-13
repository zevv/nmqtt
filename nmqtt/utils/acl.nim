## Access Control List (ACL) module for nmqtt broker
##
## Provides Mosquitto-compatible ACL file parsing and topic access control.
## Supports user-specific rules and pattern-based rules with %u (username)
## and %c (client ID) substitution.
##
## ACL file format:
##   # Comments start with #
##   user <username>
##   topic [read|write|readwrite] <topic>
##
##   pattern [read|write|readwrite] <topic>
##
## The `user` directive starts a user-specific section. All `topic` directives
## that follow apply to that user until the next `user` directive.
##
## The `pattern` directive defines rules that apply to all authenticated users.
## Patterns support %u (replaced with username) and %c (replaced with client ID).
##
## Topic wildcards:
##   # - multi-level wildcard (matches any number of levels)
##   + - single-level wildcard (matches exactly one level)

import strutils, tables

type
  AclAccess* = enum
    AclRead = "read"
    AclWrite = "write"
    AclReadWrite = "readwrite"

  AclRule* = object
    topic*: string
    access*: AclAccess

  AclStore* = ref object
    ## Holds all parsed ACL rules
    userRules*: Table[string, seq[AclRule]]   ## Per-user rules (keyed by username)
    patternRules*: seq[AclRule]               ## Pattern rules (apply to all users)
    loaded*: bool                             ## Whether an ACL file has been loaded


proc newAclStore*(): AclStore =
  AclStore(
    userRules: initTable[string, seq[AclRule]](),
    patternRules: @[],
    loaded: false
  )


proc parseAccess(token: string): AclAccess =
  ## Parse an access keyword. Defaults to readwrite if not specified.
  case token.toLowerAscii()
  of "read": AclRead
  of "write": AclWrite
  of "readwrite": AclReadWrite
  else: AclReadWrite


proc loadAclFile*(store: AclStore, filename: string) =
  ## Parse a Mosquitto-compatible ACL file and populate the store.
  var currentUser = ""

  for rawLine in readFile(filename).splitLines():
    let line = rawLine.strip()

    # Skip empty lines and comments
    if line.len == 0 or line[0] == '#':
      continue

    let parts = line.splitWhitespace()
    if parts.len == 0:
      continue

    case parts[0].toLowerAscii()
    of "user":
      # Start a new user section
      if parts.len >= 2:
        currentUser = parts[1]
        if not store.userRules.hasKey(currentUser):
          store.userRules[currentUser] = @[]

    of "topic":
      # Topic rule under a user section
      var access: AclAccess
      var topic: string

      if parts.len == 3:
        # topic <access> <topic>
        access = parseAccess(parts[1])
        topic = parts[2]
      elif parts.len == 2:
        # topic <topic> (defaults to readwrite)
        access = AclReadWrite
        topic = parts[1]
      else:
        continue

      let rule = AclRule(topic: topic, access: access)

      if currentUser != "":
        store.userRules[currentUser].add(rule)
      # If no user section is active, ignore the topic line per Mosquitto behavior

    of "pattern":
      # Pattern rule (applies to all authenticated users)
      var access: AclAccess
      var topic: string

      if parts.len == 3:
        access = parseAccess(parts[1])
        topic = parts[2]
      elif parts.len == 2:
        access = AclReadWrite
        topic = parts[1]
      else:
        continue

      store.patternRules.add(AclRule(topic: topic, access: access))

    else:
      discard

  store.loaded = true


proc topicMatchesFilter*(topic, filter: string): bool =
  ## Check if a concrete topic matches a filter pattern with MQTT wildcards.
  ## Supports # (multi-level) and + (single-level) wildcards.
  if filter == "#":
    return true

  let topicParts = topic.split('/')
  let filterParts = filter.split('/')

  var ti = 0
  var fi = 0

  while fi < filterParts.len:
    if filterParts[fi] == "#":
      # # matches everything from here on, including zero levels
      return true

    if ti >= topicParts.len:
      # Topic is shorter than filter, no match
      return false

    if filterParts[fi] == "+":
      # + matches exactly one level
      ti += 1
      fi += 1
      continue

    if filterParts[fi] != topicParts[ti]:
      return false

    ti += 1
    fi += 1

  # Both must be fully consumed for a match (unless filter ended with #)
  return ti == topicParts.len and fi == filterParts.len


proc substitutePattern(pattern, username, clientid: string): string =
  ## Replace %u with username and %c with client ID in a pattern topic.
  result = pattern
  result = result.replace("%u", username)
  result = result.replace("%c", clientid)


proc checkAccess*(store: AclStore, username, clientid, topic: string,
                  wantWrite: bool): bool =
  ## Check whether a user is allowed to access a topic.
  ##
  ## If no ACL file is loaded, all access is allowed (open broker).
  ## If an ACL file is loaded, access is denied by default unless a
  ## matching rule grants it.
  ##
  ## `wantWrite` = true for publish, false for subscribe.

  if not store.loaded:
    return true  # No ACL loaded, allow everything

  # Check user-specific rules
  if store.userRules.hasKey(username):
    for rule in store.userRules[username]:
      if topicMatchesFilter(topic, rule.topic):
        case rule.access
        of AclReadWrite:
          return true
        of AclRead:
          if not wantWrite:
            return true
        of AclWrite:
          if wantWrite:
            return true

  # Check pattern rules (apply to all authenticated users)
  for rule in store.patternRules:
    let expandedTopic = substitutePattern(rule.topic, username, clientid)
    if topicMatchesFilter(topic, expandedTopic):
      case rule.access
      of AclReadWrite:
        return true
      of AclRead:
        if not wantWrite:
          return true
      of AclWrite:
        if wantWrite:
          return true

  # Default deny when ACL is loaded
  return false


proc checkPublish*(store: AclStore, username, clientid, topic: string): bool =
  ## check if a user can publish (write) to a topic.
  store.checkAccess(username, clientid, topic, wantWrite = true)


proc checkSubscribe*(store: AclStore, username, clientid, topic: string): bool =
  ## check if a user can subscribe (read) to a topic.
  store.checkAccess(username, clientid, topic, wantWrite = false)
