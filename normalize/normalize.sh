#!/bin/sh

"$FFMPEG" -i "$1" -ar 16000 "$2".wav
