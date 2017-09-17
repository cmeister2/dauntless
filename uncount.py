#!/usr/bin/env python3

import nltk_pinyin
import re
import sys

COUNT_LINE = re.compile("^\s*(\d+)\s([^\s]+)")


if __name__ == "__main__":
    detector = nltk_pinyin.Detector()
    counter = 0

    with sys.stdin as fh:
        for line in fh:
            m = COUNT_LINE.match(line)
            if not m:
                continue

            subdomain = m.group(2)
            print(subdomain)
