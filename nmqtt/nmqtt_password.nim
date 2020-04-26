import
  cligen,
  utils/passwords

from os import fileExists
from strutils import format, split
from terminal import readPasswordFromStdin

import utils/version


proc addUserToFile(filename, username, password: string) =
  ## Adds a new user
  let
    salt    = makeSalt()
    pwdHash = makePassword(password, salt)
    storage = username & ":" & pwdHash & salt

  var buffer: string
  if fileExists(filename):
    for line in filename.lines:
      if line.split(":")[0] == username:
        echo "Error, username does already exist.\n"
        quit()
      if buffer != "":
        buffer.add("\n")
      buffer.add($line)
    if buffer != "":
      buffer.add("\n")
  buffer.add(storage)

  writeFile(filename, buffer)

  echo "User added to password file\n"


proc deleteUserToFile(filename, username: string) =
  ## Deletes a user
  if not fileExists(filename):
    echo "\nPassword file does not exist: " & filename & "\n"
    quit()

  var buffer: string
  for line in filename.lines:
    if line.split(":")[0] == username:
      continue
    if buffer != "":
      buffer.add("\n")
    buffer.add($line)

  writeFile(filename, buffer)

  echo "User deleted from password file\n"


proc nmqttPassword(adduser=false, batch=false, deluser=false, args: seq[string]) =
  ## Main handler
  echo "Running nmqtt_password v" & nmqttVersion

  if args.len() == 0:
    echo "Error, missing parameters. Run again with --help."
    quit()

  echo "\nEditing password_file\n - " & args[0] & "\n"

  if adduser:
    if args.len() != 2:
      echo "Please provide a path to the password file and a username.\n" &
           " - nmqtt_password -a {password_file.conf} {username}"
      quit()
    let
      prompt   = "Username: $1\nPassword: ".format(args[1])
      password = readPasswordFromStdin(prompt)
    addUserToFile(args[0], args[1], password)

  elif batch:
    if args.len() != 3:
      echo "Please provide a path to the password file, a username and password.\n" &
           " - nmqtt_password -b {password_file.conf} {username} {password}"
      quit()
    addUserToFile(args[0], args[1], args[2])

  elif deluser:
    if args.len() != 2:
      echo "Please provide a path to the password file and a username.\n" &
           " - nmqtt_password -d {password_file.conf} {username}"
      quit()
    deleteUserToFile(args[0], args[1])

  else:
    echo "Please provide an action option: -a, -b or -d\n"
    quit()


when isMainModule:
  const topLvlUse = """nmqtt_password is a user and password manager for nmqtt
nmqtt_password is based upon nmqtt version """ & nmqttVersion & """


USAGE
  $command -a {password_file.conf} {username}
  $command -b {password_file.conf} {username} {password}
  $command -d {password_file.conf} {username}

CONFIG
  Add or delete users from nmqtt password file.

OPTIONS
$options
"""
  clCfg.hTabCols = @[clOptKeys, clDescrip]

  dispatchGen(nmqttPassword,
          cmdName="nmqtt_password",
          help={
            "adduser":  "add a new user to the password file.",
            "batch":    "run in batch mode to allow passing passwords on the command line.",
            "deluser":  "delete a user from the password file.",
          },
          short={
            "help": '?',
          },
          usage=topLvlUse,
          dispatchName="passwordCli"
          )

  cligenQuit passwordCli(skipHelp=true)