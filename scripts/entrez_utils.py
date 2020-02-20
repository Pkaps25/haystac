#!/usr/bin/env python
# -*- coding: utf-8 -*-
import http.client
import sys
import time
import urllib.error

from Bio import Entrez

# the maximum number of attempts to make for a failed query
MAX_RETRY_ATTEMPTS = 2

# time to wait in seconds before repeating a failed query
RETRY_WAIT_TIME = 2


def chunker(seq, size):
    return (seq[pos:pos + size] for pos in range(0, len(seq), size))


def entrez_efetch(config, db, retstart, webenv, query_key, attempt=1):

    try:
        return Entrez.efetch(db=db,
                             retmode=config['entrez']['retmode'],
                             rettype=config['entrez']['rettype'],
                             retmax=config['entrez']['batchSize'],
                             retstart=retstart,
                             webenv=webenv,
                             query_key=query_key)

    except http.client.HTTPException as e:
        print("Network problem: {}".format(e), file=sys.stderr)

        attempt += 1

        if attempt > MAX_RETRY_ATTEMPTS:
            print("Exceeded maximum attempts {}...".format(attempt), file=sys.stderr)
            return None
        else:
            time.sleep(RETRY_WAIT_TIME)
            print("Starting attempt {}...".format(attempt), file=sys.stderr)
            return entrez_efetch(config, db, retstart, webenv, query_key, attempt)

    except (http.client.IncompleteRead, urllib.error.URLError) as e:
        print("Ditching that batch", file=sys.stderr)
        print(e)
        return None