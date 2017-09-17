#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NLTK based detector for pinyin subdomains"""

from __future__ import (absolute_import, division, print_function,
                        unicode_literals)
import logging
import os
import pickle
import random
import re
import sys
import nltk
from nltk.classify import apply_features
import nltk_pinyin as nlp
from .syllables import SYLLABLES

log = logging.getLogger(__name__)
CLASSIFIER_NAME = os.path.join(nlp.PACKAGE_PATH, "pinyin_classifier.pkl")


# Set up some regular expressions which match pinyin domains
PINYIN_RE = re.compile(r"^({0})+$".format("|".join(SYLLABLES)))
PINYINNUM_RE = re.compile(r"^(\d+)?({0})+(\d+)?$".format("|".join(SYLLABLES)))


class DomainTypes(object):
    PINYIN = 1
    NONPINYIN = 2
    DESC = {
        1: "pinyin",
        2: "nonpinyin",
    }


def pinyin_features(subdomain):
    """
    A function which extracts information about the subdomain and tld pair in hand.
    :param subdomain_tld: A colon joined tuple of subdomain and TLD.
    :return: a dictionary of feature information.
    """
    domain_lower = subdomain.lower()

    # Start to build up a dictionary of features.
    features = {
        "length": len(subdomain)
    }

    syllable_count = 0
    for syllable in nlp.SYLLABLES:
        key = "has({0})".format(syllable)
        features[key] = (syllable in domain_lower)

    for syllable in nlp.COMPOUND_SYLLABLES:
        key = "has({0})".format(syllable)
        features[key] = (syllable in domain_lower)

    features["is(pinyin)"] = True if PINYIN_RE.match(domain_lower) else False
    features["is(pinyinnum)"] = True if PINYINNUM_RE.match(domain_lower) else False
    return features


class Detector(object):
    WHITELIST = [
        "api",
        "exchange",
        "owa",
        "pine",
        "remote",
        "secure",
    ]

    BLACKLIST = [
        "baile",
        "ttyule",
        "zhube",
    ]

    def __init__(self):
        self.pinyin_path = os.path.join(nlp.PACKAGE_PATH, "pinyinsub.txt")
        self.nonpinyin_path = os.path.join(nlp.PACKAGE_PATH, "nonpinyinsub.txt")
        self.classifier = self.get_classifier()

    def get_pinyin_set(self):
        with open(self.pinyin_path, "rb") as f:
            pinyin = [(dataline.decode("utf-8").rstrip(), DomainTypes.PINYIN)
                      for dataline in f]
        log.info("Loaded pinyin from %s", self.pinyin_path)
        return pinyin

    def get_nonpinyin_set(self):
        with open(self.nonpinyin_path, "rb") as f:
            nonpinyin = [(dataline.decode("utf-8").rstrip().lower(), DomainTypes.NONPINYIN)
                         for dataline in f]
        log.info("Loaded nonpinyin from %s", self.nonpinyin_path)
        return nonpinyin

    def get_classifier(self):
        if os.path.isfile(CLASSIFIER_NAME):
            with open(CLASSIFIER_NAME, "rb") as f:
                classifier = pickle.load(f)
                return classifier

        pinyin = self.get_pinyin_set()
        nonpinyin = self.get_nonpinyin_set()
        combined = pinyin + nonpinyin
        combined_len = len(combined)
        log.debug("Loaded %d records", combined_len)

        log.info("Training classifier")
        train_set = apply_features(pinyin_features, combined)
        classifier = nltk.NaiveBayesClassifier.train(train_set)
        log.info("Classifier trained")

        with open(CLASSIFIER_NAME, "wb") as f:
            pickle.dump(classifier, f)

        return classifier

    def test_features(self):
        pinyin = self.get_pinyin_set()
        nonpinyin = self.get_nonpinyin_set()
        combined = pinyin + nonpinyin

        # Shuffle the combined data set.
        random.shuffle(combined)

        combined_len = len(combined)
        log.debug("Loaded %d records", combined_len)

        test_index = int(combined_len * 3 / 4)

        log.info("Training classifier")
        train_set = apply_features(pinyin_features, combined[:test_index])
        test_set = apply_features(pinyin_features, combined[test_index:])
        classifier = nltk.NaiveBayesClassifier.train(train_set)
        accuracy = nltk.classify.accuracy(classifier, test_set)
        log.info("Classifier trained; accuracy %f", accuracy)

        for (name, tag) in combined[test_index:]:
            is_pinyin = (tag == DomainTypes.PINYIN)
            guess_pinyin = self.is_pinyin(name, classifier)

            if guess_pinyin != is_pinyin:
                log.info("%-30s: guessed pinyin %s, was pinyin %s",
                         name,
                         guess_pinyin,
                         is_pinyin)

        classifier.show_most_informative_features(10)

    def is_pinyin(self, subdomain, classifier=None):
        if classifier is None:
            classifier = self.classifier

        # log.debug("Trying to classify %s", subdomain)

        # Do the fast checks first
        if subdomain in self.WHITELIST:
            return False
        elif subdomain in self.BLACKLIST:
            return True

        # # Test against the numerical pinyin regex.
        # m = PINYINNUM_RE.match(subdomain)
        # if m:
        #     return True

        probs = classifier.prob_classify(pinyin_features(subdomain))
        # log.info("Probs: %s", probs)

        result = probs.max()

        if result == DomainTypes.PINYIN:
            return True
        else:
            return False
