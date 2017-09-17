#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import logging
import sys
import nltk_pinyin as nlp


if __name__ == "__main__":

    logging.basicConfig(format="%(levelname)-5.5s %(message)s",
                        stream=sys.stdout,
                        level=logging.DEBUG)

    d = nlp.Detector()
    d.test_features()
