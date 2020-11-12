#!/usr/bin/env python
# -*- coding: utf-8 -*-

__author__ = "Evangelos A. Dimopoulos, Evan K. Irving-Pease"
__copyright__ = "Copyright 2020, University of Oxford"
__email__ = "antonisdim41@gmail.com"
__license__ = "MIT"

from math import ceil

import pandas as pd
from psutil import virtual_memory

MEGABYTE = float(1024 ** 2)
MAX_MEM_MB = virtual_memory().total / MEGABYTE

from haystack.workflow.scripts.utilities import get_total_paths


def get_db_list(_):
    """Get fasta paths in our db"""
    return [
        config["cache"] + f"/ncbi/{orgname}/{accession}.fasta.gz"
        for orgname, accession in get_total_paths(checkpoints, config)
    ]


rule random_db_paths:
    input:
        get_db_list,
    log:
        config["db_output"] + "/bowtie/bt2_random_fasta_paths.log",
    output:
        config["db_output"] + "/bowtie/bt2_random_fasta_paths.txt",
    params:
        seed=config["seed"],
    message:
        "The database genomes are being placed in a random order."
    script:
        "../scripts/random_db_paths.py"


checkpoint calculate_bt2_idx_chunks:
    input:
        config["db_output"] + "/bowtie/bt2_random_fasta_paths.txt",
    log:
        config["db_output"] + "/bowtie/bt2_idx_chunk_num.log",
    output:
        config["db_output"] + "/bowtie/bt2_idx_chunk_list.txt",
        config["db_output"] + "/bowtie/bt2_idx_chunk_num.txt",
    params:
        query=config["db_output"],
        mem_resources=float(config["mem"]),
        mem_rescale_factor=config["bowtie2_scaling"],
    message:
        "The number of index chunks needed for the filtering alignment are being calculated."
    script:
        "../scripts/calculate_bt2_idx_chunks.py"


def get_bt2_idx_filter_chunk(wildcards):
    """Pick the files for the specific bt2 index chunk"""

    # read the file with the chunks
    # noinspection PyUnresolvedReferences
    get_chunk_num = checkpoints.calculate_bt2_idx_chunks.get()
    chunk_df = pd.read_csv(get_chunk_num.output[0], sep="\t", names=["chunk", "path"])

    # store the paths belonging to a chunk in a list
    fasta_paths_random = chunk_df[chunk_df["chunk"] == int(wildcards.chunk_num)]["path"].to_list()

    return fasta_paths_random


rule create_bt2_idx_filter_chunk:
    input:
        get_bt2_idx_filter_chunk,
    log:
        config["db_output"] + "/bowtie/bt2_idx_filter_{chunk_num}.log",
    output:
        config["db_output"] + "/bowtie/chunk{chunk_num}.fasta.gz",
    message:
        "Creating chunk {wildcards.chunk_num} of the genome database index."
    shell:
        "cat {input} > {output}"


rule bowtie_index:
    input:
        fasta_chunk=config["db_output"] + "/bowtie/chunk{chunk_num}.fasta.gz",
    log:
        config["db_output"] + "/bowtie/chunk{chunk_num}_index.log",
    output:
        config["db_output"] + "/bowtie/chunk{chunk_num}.1.bt2l",
        config["db_output"] + "/bowtie/chunk{chunk_num}.2.bt2l",
        config["db_output"] + "/bowtie/chunk{chunk_num}.3.bt2l",
        config["db_output"] + "/bowtie/chunk{chunk_num}.4.bt2l",
        config["db_output"] + "/bowtie/chunk{chunk_num}.rev.1.bt2l",
        config["db_output"] + "/bowtie/chunk{chunk_num}.rev.2.bt2l",
    benchmark:
        repeat("benchmarks/bowtie_index_chunk{chunk_num}.benchmark.txt", 1)
    message:
        "Bowtie2 index for chunk {input.fasta_chunk} is being built."
    threads: int(config["cores"] / 2)
    conda:
        "../envs/bowtie2.yaml"
    params:
        basename=config["db_output"] + "/bowtie/chunk{chunk_num}",
    priority: 1
    shell:
        "bowtie2-build --large-index --threads {config[cores]} {input.fasta_chunk} {params.basename} &> {log}"


def get__bt2_idx_chunk_paths(_):
    """Get the paths for the index chunks for the filtering bowtie2 alignment"""

    # noinspection PyUnresolvedReferences
    get_chunk_num = checkpoints.calculate_bt2_idx_chunks.get()
    idx_chunk_total = ceil(float(open(get_chunk_num.output[1]).read().strip()))

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
        "The bowtie2 indices of the genome database have been built."
    shell:
        "touch {output}"
