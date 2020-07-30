#!/usr/bin/env python
# -*- coding: utf-8 -*-

__author__ = "Evangelos A. Dimopoulos, Evan K. Irving-Pease"
__copyright__ = "Copyright 2020, University of Oxford"
__email__ = "antonisdim41@gmail.com"
__license__ = "MIT"

import os
from math import ceil

from psutil import virtual_memory


MEGABYTE = float(1024 ** 2)
MAX_MEM_MB = virtual_memory().total / MEGABYTE


##### Target rules #####

from scripts.rip_utilities import get_total_paths, normalise_name


def get_total_fasta_paths(wildcards):
    """
    Get all the individual fasta file paths for the taxa in our database.
    """

    sequences = get_total_paths(
        wildcards,
        checkpoints,
        config["with_entrez_query"],
        config["refseq_rep"],
        config["with_custom_sequences"],
        config["with_custom_accessions"],
        config["genera"],
    )

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = (
            normalise_name(seq["species"]),
            seq["GBSeq_accession-version"],
        )

        inputs.append(
            config["genome_cache_folder"]
            + "/{orgname}/{accession}.fasta.gz".format(
                orgname=orgname, accession=accession,
            )
        )

    return inputs


checkpoint calculate_bt2_idx_chunks:
    input:
        get_total_fasta_paths,
    log:
        config["db_output"] + "/bowtie/bt2_idx_chunk_num.log",
    output:
        config["db_output"] + "/bowtie/bt2_idx_chunk_num.txt",
    params:
        query=config["db_output"],
        mem_resources=float(config["mem"]),
        mem_rescale_factor=config["bowtie2_scaling"],
    message:
        "The number of index chunks for the filtering alignment are being calculated for query {params.query}. "
        "The size rescaling factor for the chunk is {params.mem_rescale_factor} for the given memory "
        "resources {params.mem_resources}. The log file can be found in {log}."
    conda:
        "../envs/calc_bt2_idx_chunks.yaml"
    script:
        "../scripts/calculate_bt2_idx_chunks.py"


def get_bt2_idx_filter_chunk(wildcards):

    """Pick the files for the specific bt2 index chunk"""

    chunk_files = []
    chunk_size = float(config["mem"]) / float(config["bowtie2_scaling"])
    total_size = 0.0

    for fasta_file in get_total_fasta_paths(wildcards):
        total_size += os.stat(fasta_file).st_size / MEGABYTE

        chunk = (total_size // chunk_size) + 1

        if chunk == int(wildcards.chunk_num):
            chunk_files.append(fasta_file)
        elif chunk > int(wildcards.chunk_num):
            break

    return chunk_files


rule create_bt2_idx_filter_chunk:
    input:
        get_bt2_idx_filter_chunk,
    log:
        config["db_output"] + "/bowtie/bt2_idx_filter_{chunk_num}.log",
    output:
        config["db_output"] + "/bowtie/chunk{chunk_num}.fasta.gz",
    message:
        "Creating fasta chunk {wildcards.chunk_num} for the filtering alignment bowtie2 index for "
        "the given query.The output can be found in {output} and its log can be found in {log}."
    conda:
        "../envs/bt2_multifasta.yaml"
    script:
        "../scripts/bowtie2_multifasta.py"


rule bowtie_index:
    input:
        fasta_chunk=config["db_output"] + "/bowtie/chunk{chunk_num}.fasta.gz",
    log:
        config["db_output"] + "/bowtie/chunk{chunk_num}_index.log",
    output:
        expand(
            config["db_output"] + "/bowtie/chunk{chunk_num}.{n}.bt2l",
            n=[1, 2, 3, 4],
            allow_missing=True,
        ),
        expand(
            config["db_output"] + "/bowtie/chunk{chunk_num}.rev.{n}.bt2l",
            n=[1, 2],
            allow_missing=True,
        ),
    benchmark:
        repeat("benchmarks/bowtie_index_chunk{chunk_num}.benchmark.txt", 1)
    message:
        "Bowtie2 index for chunk {input.fasta_chunk} is being built. The log file can be found in {log}."
    conda:
        "../envs/bowtie2.yaml"
    shell:
        "bowtie2-build --large-index {input.fasta_chunk} "+
         config['db_output']+"/bowtie/chunk{wildcards.chunk_num} &> {log}"


def get__bt2_idx_chunk_paths(wildcards):

    """Get the paths for the index chunks for the filtering bowtie2 alignment"""

    get_chunk_num = checkpoints.calculate_bt2_idx_chunks.get()
    idx_chunk_total = ceil(float(open(get_chunk_num.output[0]).read().strip()))

    return expand(
        config["db_output"] + "/bowtie/chunk{chunk_num}.1.bt2l",
        chunk_num=[x + 1 if idx_chunk_total > 1 else 1 for x in range(idx_chunk_total)],
    )


rule bowtie_index_done:
    input:
        get__bt2_idx_chunk_paths,
    output:
        config["db_output"] + "/bowtie/bowtie_index.done",
    benchmark:
        repeat("benchmarks/bowtie_index_done", 1)
    message:
        "The bowtie2 indices for all the chunks {input} have been built."
    shell:
        "touch {output}"