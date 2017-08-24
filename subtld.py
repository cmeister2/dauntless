#!/usr/bin/env python3

import tldextract
import sys


# Use tldextract to extract the domain information and print it to the stdout.
def process_line(line):
    try:
        res = tldextract.extract(line)
        if not res.subdomain or not res.suffix:
            # A piece of information is missing
            return
        print("{r.subdomain}:{r.suffix}".format(r=res))
    except:
        pass


if __name__ == "__main__":
    with sys.stdin as fh:
        for line in fh:
            process_line(line.rstrip())
