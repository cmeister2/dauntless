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

PINYIN_RE = re.compile(r"^({0})+$".format("|".join(SYLLABLES)))
CLASSIFIER_NAME = os.path.join(nlp.PACKAGE_PATH, "pinyin_classifier.pkl")


class DomainTypes(object):
    PINYIN = 1
    NONPINYIN = 2
    DESC = {
        1: "pinyin",
        2: "nonpinyin",
    }


def pinyin_features(subdomain_tld):
    """
    A function which extracts information about the subdomain and tld pair in hand.
    :param subdomain_tld: A colon joined tuple of subdomain and TLD.
    :return: a dictionary of feature information.
    """
    subdomain, tld = subdomain_tld.rsplit(":", 1)
    domain_lower = subdomain.lower()

    # Start to build up a dictionary of features.
    features = {
        "tld": tld,
        "length": len(subdomain)
    }

    syllable_count = 0
    for syllable in nlp.SYLLABLES:
        key = "has({0})".format(syllable)
        if syllable in domain_lower:
            features[key] = True
            syllable_count += 1
        else:
            features[key] = False

    #features["syllablecount"] = syllable_count
    features["allpinyin"] = True if PINYIN_RE.match(domain_lower) else False
    features["yule"] = domain_lower.endswith("yule")
    return features


class Detector(object):
    WHITELIST = [
        "exchange"
    ]

    def __init__(self):
        self.pinyin_path = os.path.join(nlp.PACKAGE_PATH, "pinyin.txt")
        self.nonpinyin_path = os.path.join(nlp.PACKAGE_PATH, "nonpinyin.txt")
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
            guess = classifier.classify(pinyin_features(name))
            if guess != tag:
                log.info("%-30s: guessed %s, was %s",
                         name,
                         DomainTypes.DESC[guess],
                         DomainTypes.DESC[tag])

        classifier.show_most_informative_features(30)

    def is_pinyin(self, subdomain_tld):
        log.debug("Trying to classify %s", subdomain_tld)
        result = self.classifier.classify(pinyin_features(subdomain_tld))

        if result == DomainTypes.PINYIN:
            # Check whether the domain is on a whitelist
            subdomain, tlv = subdomain_tld.rsplit(":", 1)
            if subdomain in self.WHITELIST:
                return False

            return True
        else:
            return False

