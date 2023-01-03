#!/bin/bash

# This uses MFA devices to get temporary (eg 12 hour) credentials.  Requires
# a TTY for user input.
#
# GPL 2 or higher

while true; do
  case "$1" in
    -a | --account ) ACCOUNT=$2; shift 2 ;;
    -r | --role ) ROLE=$2; shift 2 ;;
    -s | --session-name ) SESSION_NAME=$2; shift 2 ;;
    * ) break ;;
  esac
done

if [ ! -t 0 ]
then
  echo Must be on a tty >&2
  exit 255
fi

if [ -n "$AWS_SESSION_TOKEN" ]
then
  echo "Session token found.  This can not be used to generate a new token.
   unset AWS_SESSION_TOKEN AWS_SECRET_ACCESS_KEY AWS_ACCESS_KEY_ID
and then ensure you have a profile with the normal access key credentials or
set the variables to the normal keys.
" >&2
  exit 255
fi

username=$(aws sts get-caller-identity | jq -r '.Arn' | cut -d '/' -f2 | tr -d '[[:space:]]' )
if [ -z "$username" ]
then
  echo "Can not identify who you are.  Looking for a line like
    arn:aws:iam::.....:user/FOO_BAR
but did not find one in the output of
  aws sts get-caller-identity
$identity" >&2
  exit 255
fi

if [ -z "${SESSION_NAME}"]
then
  SESSION_NAME="${username}-test"
fi

if [ -z "${ACCOUNT}" ]
then
  ACCOUNT=$(aws sts get-caller-identity | jq -r '.Account')
fi

if [ -z "${ROLE}" ]
then
  echo "Please specify a role" >&2
  exit 255
fi

echo You are: $username >&2

device=$(aws iam list-mfa-devices --user-name "${username}" | jq -r '.MFADevices[0].SerialNumber')
if [ -z "$device" ]
then
  echo "Can not find any MFA device for you.  Looking for a SerialNumber
    but did not find one in the output of aws iam list-mfa-devices --username \"$username\"
  $mfa" >&2
  exit 255
fi

echo Your MFA device is: $device >&2

echo -n "Enter your MFA code now: " >&2
read code

tokens=$(aws sts assume-role --role-arn "arn:aws:iam::${ACCOUNT}:role/${ROLE}" --role-session-name "${SESSION_NAME}" --serial-number "${device}" --token-code "${code}" )

secret=$(echo "$tokens" | jq -r .Credentials.SecretAccessKey )
session=$(echo "$tokens" | jq -r .Credentials.SessionToken )
access=$(echo "$tokens" | jq -r .Credentials.AccessKeyId )
expire=$(echo "$tokens" | jq -r .Credentials.Expiration )

if [ -z "$secret" -o -z "$session" -o -z "$access" ]
then
  echo "Unable to get temporary credentials.  Could not find secret/access/session entries ${tokens}" >&2
  exit 255
fi

export AWS_PROFILE="${AWS_PROFILE}"
export AWS_SESSION_TOKEN="${session}"
export AWS_SECRET_ACCESS_KEY="${secret}"
export AWS_ACCESS_KEY_ID="${access}"

echo "Keys valid until ${expire}" >&2