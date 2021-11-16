#!/bin/sh
 spcli node get | awk 'BEGIN {FS = "|" };  {print $1 "\t" $3 "\t" $4}'
