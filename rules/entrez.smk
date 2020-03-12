#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pandas as pd

##### Target rules #####

rule entrez_nuccore_query:
    output:
        "{query}/entrez/{query}-nuccore.tsv"
    log:
        "{query}/entrez/{query}-nuccore.log"
    script:
        "../scripts/entrez_nuccore_query.py"


rule entrez_taxa_query:
    input:
        "{query}/entrez/{query}-nuccore.tsv"
    output:
        "{query}/entrez/{query}-taxa.tsv"
    log:
        "{query}/entrez/{query}-taxa.log"
    script:
        "../scripts/entrez_taxonomy_query.py"


checkpoint entrez_pick_sequences:
    input:
         "{query}/entrez/{query}-nuccore.tsv",
         "{query}/entrez/{query}-taxa.tsv"
    output:
         "{query}/entrez/{query}-selected-seqs.tsv"
    log:
         "{query}/entrez/{query}-selected-seqs.log"
    script:
        "../scripts/entrez_pick_sequences.py"


rule entrez_download_sequence:
    output:
        # TODO we should gzip the output and change the file extension to .fa.gz
        "database/{orgname}/{accession}.fasta"
    log:
        "database/{orgname}/{accession}.log"
    script:
         "../scripts/entrez_download_sequence.py"


def get_fasta_sequences(wildcards):
    """
    Get all the FASTA sequences for the multi-FASTA file.
    """
    pick_sequences = checkpoints.entrez_pick_sequences.get(query=wildcards.query)
    sequences = pd.read_csv(pick_sequences.output[0], sep='\t')

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = seq['species'].replace(" ", "_"), seq['GBSeq_accession-version']
        inputs.append('database/{orgname}/{accession}.fasta'.format(orgname=orgname, accession=accession))

    return inputs


rule entrez_multifasta:
    input:
         get_fasta_sequences
    log:
         "{query}/bowtie/{query}.log"
    output:
         # TODO we should gzip the output and change extension to .fa.gz
         "{query}/bowtie/{query}.fasta"
    script:
          # TODO cat works with gzip, you can could do `cat {input} > {output}` as a shell command and drop the python file
          "../scripts/bowtie_multifasta.py"
