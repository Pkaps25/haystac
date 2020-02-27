#!/usr/bin/env python
# -*- coding: utf-8 -*-

import http.client
import sys
import time
import urllib.error
from datetime import datetime
from socket import error as socketerror

from Bio import Entrez

# the maximum number of attempts to make for a failed query
MAX_RETRY_ATTEMPTS = 2

# time to wait in seconds before repeating a failed query
RETRY_WAIT_TIME = 2

ENTREZ_DB_NUCCORE = 'nuccore'
ENTREZ_DB_TAXA = 'taxonomy'

ENTREZ_RETMODE_XML = 'xml'
ENTREZ_RETMODE_TEXT = 'text'

ENTREZ_RETTYPE_FASTA = 'fasta'

ENTREZ_RETMAX = 10**9


def chunker(seq, size):
    return (seq[pos:pos + size] for pos in range(0, len(seq), size))


def entrez_efetch(db, retmode, retstart, webenv, query_key, attempt=1):
    try:
        return Entrez.efetch(db=db,
                             retmode=ENTREZ_RETMODE_XML,
                             rettype=ENTREZ_RETTYPE_FASTA,
                             retmax=ENTREZ_RETMAX,
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
            return entrez_efetch(db, retmode, retstart, webenv, query_key, attempt)

    except (http.client.IncompleteRead, urllib.error.URLError) as e:
        # TODO refactor this error handling
        print("Ditching that batch", file=sys.stderr)
        print(e)
        return None


def guts_of_entrez(db, retmode, chunk, batch_size):
    # print info about number of records
    print("Downloading {} entries from NCBI {} database in batches of {} entries...\n"
          .format(len(chunk), db, batch_size), file=sys.stderr)

    # post NCBI query
    search_handle = Entrez.epost(db, id=",".join(map(str, chunk)))
    search_results = Entrez.read(search_handle)

    for start in range(0, len(chunk), batch_size):
        # print info
        now = datetime.ctime(datetime.now())
        print("\t{}\t{} / {}\n".format(now, start, len(chunk)), file=sys.stderr)

        handle = entrez_efetch(db, retmode, start, search_results["WebEnv"], search_results["QueryKey"])

        if not handle:
            continue

        if retmode == 'text':
            return handle

        print("got the handle", file=sys.stderr)

        try:
            records = Entrez.read(handle)
            print("got the records", file=sys.stderr)

        except (http.client.HTTPException, urllib.error.HTTPError, urllib.error.URLError,
                RuntimeError, Entrez.Parser.ValidationError, socketerror):
            # TODO refactor this error handling
            print("Ditching that batch of records", file=sys.stderr)
            continue

        for rec in records:
            yield rec
