
default:
  just --list

build image:
  # cd images && sh build.sh
  mise exec -- python ./images/build.py {{image}}