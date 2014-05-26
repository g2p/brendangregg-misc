#!/bin/ksh
#
# kernel_diagreport2text.ksh 
#
# Prints the stack trace from an OS X kernel panic diagnostic report, along
# with as much symbol translation as your mach_kernel version provides.
# By default, this is some, but with the Kernel Debug Kit, it should be a lot
# more. This is not an official Apple tool. 
#
# Note: The Kernel Debug Kit currently requires an Apple ID to download. It
# would be great if this was not necessary.
#
# This script calls atos(1) for symbol translation, and also some sed/awk
# to decorate remaining untranslated symbols with kernel extension names,
# if the ranges match.
#
# Copyright 2014 Brendan Gregg.  All rights reserved.
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at docs/cddl1.txt or
# http://opensource.org/licenses/CDDL-1.0.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at docs/cddl1.txt.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END

kernel=/mach_kernel

if (( $# == 0 )); then
	print "USAGE: $0 Kernel_diag_report.panic [...]"
	print "   eg, $0 /Library/Logs/DiagnosticReports/Kernel_2014-05-26-124827_bgregg.panic"
	exit
fi

if [[ ! -x /usr/bin/atos ]]; then
	print "ERROR: Couldn't find, and need, /usr/bin/atos. Is this part of Xcode? Quitting..."
	exit
fi

while (( $# != 0 )); do
	if [[ "$file" != "" ]]; then print; fi
	file=$1
	shift
	echo "File $file"

	if [[ ! -e $file ]]; then
		print "ERROR: File $file not found. Skipping."
		continue
	fi

	# Find slide address
	slide=$(awk '/^Kernel slide:.*0x/ { print $3 }' $file)
	if [[ "$slide" == "" ]]; then
		print -n "ERROR: Missing \"Kernel slide:\" line, so can't process $file. "
		print "This is needed for atos -s. Is this really a Kernel diag panic file?"
		continue
	fi

	# Find kernel extension ranges
	i=0
	unset name
	unset start
	unset end
	awk 'ext == 1 && /0x.*->.*0x/ { print $0 }
		/Kernel Extensions in backtrace/ { ext = 1 }
		/^$/ { ext = 0 }
	' < $file | sed 's/\[.*\]//;s/@/ /;s/->/ /' | while read n s e; do
		# the previous sed line converts this:
		#   com.apple.driver.AppleUSBHub(666.4)[CD9B71FF-2FDD-3BC4-9C39-5E066F66D158]@0xffffff7f84ed2000->0xffffff7f84ee9fff
		# into this:
		#   com.apple.driver.AppleUSBHub(666.4) 0xffffff7f84ed2000 0xffffff7f84ee9fff
		# which can then be read as three fields
		name[i]=$n
		start[i]=$s
		end[i]=$e
		(( i++ ))
	done

	# Print and translate stack
	print "Stack:"
	awk 'backtrace == 1 && /^[^ ]/ { print $3 }
		/Backtrace.*Return Address/ { backtrace = 1 }
		/^$/ { backtrace = 0 }
	' < $file | atos -d -o $kernel -s $slide | while read line; do
		# do extensions
		if [[ $line =~ 0x* ]]; then
			i=0
			while (( i <= ${#name[@]} )); do
				if [[ "${start[i]}" == "" ]]; then break; fi
				# assuming fixed width addresses, use string comparison:
				if [[ $line > ${start[$i]} && $line < ${end[$i]} ]]; then
					line="$line (in ${name[$i]})"
					break
				fi
				(( i++ ))
			done
		fi
		print "	$line"
	done

	# Print other key details
	awk '/^BSD process name/ { print "BSD process name:", $NF }
		ver == 1 { print "Mac OS version:", $0; ver = 0 }
		/^Mac OS version/ { ver = 1 }
	' < $file
done
