import md5, bcrypt, random


var urandom: File
let useUrandom = urandom.open("/dev/urandom")


template makeSessionKey*(): string =
  ## Creates a random key to be used to authorize a session.
  bcrypt.hash(makeSalt(), genSalt(8))

template makePassword*(password, salt: string, comparingTo = ""): string =
  ## Creates an MD5 hash by combining password and salt.
  bcrypt.hash(getMD5(salt & getMD5(password)), if comparingTo != "": comparingTo else: genSalt(8))

proc makeSalt*(): string =
  ## Generate random salt. Uses cryptographically secure /dev/urandom
  ## on platforms where it is available, and Nim's random module in other cases.
  if likely(useUrandom):
    var randomBytes: array[0..127, char]
    discard urandom.readBuffer(addr(randomBytes), 128)
    for ch in randomBytes:
      if ord(ch) in {32..126}:
        result.add(ch)
  else:  # Fallback to Nim random when no /dev/urandom
    for i in 0..127:
      result.add(chr(rand(94) + 32)) # Generate numbers from 32 to 94 + 32 = 126