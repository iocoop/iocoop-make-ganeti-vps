#!/usr/bin/env python3
#
# Author: Ben Kochie <ben@nerp.net>
#
# Description: Take a SSH key string like "ssh-rsa ... foo@bar.com" and make sure it's properly formatted

import sys
import base64
import struct

if len(sys.argv) != 2:
  print("usage: " + sys.argv[0] + " <keystring>")
  exit(1)

sshkey = sys.argv[1].split()

# And the number of counting shal be 3
if len(sshkey) != 3:
  print("ERROR: Invalid key")
  exit(1)

key_type, key_string, comment = sshkey

try:
  data = base64.b64decode(key_string)
except:
  print("ERROR: Unable to decode key string: " + key_string)
  exit(1)

int_len = 4
str_len = struct.unpack('>I', data[:int_len])[0] # this should return 7

type_decode = data[int_len:int_len+str_len].decode()

if key_type != type_decode:
  print("ERROR: Type: " + key_type + " Type decoded: " + type_decode + " did not match")
  exit(1)

if "@" not in comment:
  print("ERROR: Comment '" + comment + "' may not be a valid email address")
  exit(1)

print("INFO: SSH Key OK: " + comment)
