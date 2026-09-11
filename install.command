#!/bin/zsh
set -eu

ROOT="${0:A:h}"
exec /usr/bin/env zsh "$ROOT/install.sh"
