#!/usr/bin/env python3

import nltk_pinyin
import re
import sys

COUNT_LINE = re.compile("^\s*(\d+)\s([^\s]+)")


if __name__ == "__main__":
    detector = nltk_pinyin.Detector()
    with sys.stdin as fh:
        for line in fh:
            m = COUNT_LINE.match(line)
            if not m:
                continue

            subdomain = m.group(2)

            if not detector.is_pinyin(subdomain):
                # Just write the line out directly to stdout
                sys.stdout.write(line)
            else:
                # Write the line to stderr so we have a record of domains
                # which may have been wrongly attributed.
                sys.stderr.write(line)
