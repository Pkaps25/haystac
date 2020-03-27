#!/usr/bin/env python
# -*- coding: utf-8 -*-

import csv
import os
import sys

from Bio import Entrez

sys.path.append(os.getcwd())

from scripts.entrez_utils import guts_of_entrez, ENTREZ_DB_NUCCORE, ENTREZ_RETMODE_XML, ENTREZ_RETTYPE_GB, ENTREZ_RETMAX


def entrez_find_accessions(config, query, output_file):

    Entrez.email = config['entrez']['email']

    entrez_query = config['entrez']['queries'][query]

    handle = Entrez.esearch(db=ENTREZ_DB_NUCCORE, term=entrez_query, retmax=ENTREZ_RETMAX, idtype="acc",
                            rettype=ENTREZ_RETTYPE_GB, retmode=ENTREZ_RETMODE_XML)

    handle_reader = Entrez.read(handle)

    accessions = handle_reader['IdList']

    with open(output_file, 'wb') as fout:

        fieldnames = ['GBSeq_accession-version']
        w = csv.DictWriter(fout, fieldnames, delimiter='\t', extrasaction="ignore")
        w.writeheader()

        for accession in accessions:
            w.writerow(accession)


if __name__ == '__main__':
    # redirect all output to the log
    sys.stderr = open(snakemake.log[0], 'w')

    entrez_find_accessions(
        config=snakemake.config,
        query=snakemake.wildcards.query,
        output_file=snakemake.output[0]
    )