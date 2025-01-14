#!/usr/bin/env python
# -*- coding: utf-8 -*-

__author__ = "Evangelos A. Dimopoulos, Evan K. Irving-Pease"
__copyright__ = "Copyright 2020, University of Oxford"
__email__ = "antonisdim41@gmail.com"
__license__ = "MIT"

import os


rule sra_tools_disable_cache:
    output:
        os.path.expanduser("~/.ncbi/user-settings.mkfg"),
    message:
        "Disabling the SRA toolkit cache."
    shell:
        "mkdir -p ~/.ncbi && echo '/repository/user/main/public/cache-disabled = \"true\"' > {output}"


rule get_sra_fastq_se:
    input:
        os.path.expanduser("~/.ncbi/user-settings.mkfg"),
    output:
        temp(config["sample_output_dir"] + "/sra_data/SE/{accession}.fastq"),
    log:
        config["sample_output_dir"] + "/sra_data/SE/{accession}.log",
    threads: min(6, config["cores"])
    message:
        "Download SRA file for accession {wildcards.accession}."
    conda:
        "../envs/sra_tools.yaml"
    params:
        basename=config["sample_output_dir"] + "/sra_data/SE/",
    shell:
        "fasterq-dump {wildcards.accession}"
        " --split-files"
        " --threads {threads}"
        " --temp {params.basename}"
        " --outdir {params.basename} &> {log}"


rule get_sra_fastq_pe:
    input:
        os.path.expanduser("~/.ncbi/user-settings.mkfg"),
    output:
        temp(config["sample_output_dir"] + "/sra_data/PE/{accession}_1.fastq"),
        temp(config["sample_output_dir"] + "/sra_data/PE/{accession}_2.fastq"),
    log:
        config["sample_output_dir"] + "/sra_data/PE/{accession}.log",
    threads: min(6, config["cores"])
    message:
        "Download SRA files for accession {wildcards.accession}."
    conda:
        "../envs/sra_tools.yaml"
    params:
        basename=config["sample_output_dir"] + "/sra_data/PE/",
    shell:
        "fasterq-dump {wildcards.accession}"
        " --split-files"
        " --threads {threads}"
        " --temp {params.basename}"
        " --outdir {params.basename} &> {log}"


rule compress_sra_fastq_se:
    input:
        config["sample_output_dir"] + "/sra_data/SE/{accession}.fastq",
    output:
        config["sample_output_dir"] + "/sra_data/SE/{accession}.fastq.gz",
    message:
        "Compressing the raw fastq file {input}."
    threads: 8
    conda:
        "../envs/samtools.yaml"
    shell:
        "bgzip --stdout --threads {threads} {input} 1> {output}"


rule compress_sra_fastq_pe:
    input:
        r1=config["sample_output_dir"] + "/sra_data/PE/{accession}_1.fastq",
        r2=config["sample_output_dir"] + "/sra_data/PE/{accession}_2.fastq",
    output:
        r1=config["sample_output_dir"] + "/sra_data/PE/{accession}_R1.fastq.gz",
        r2=config["sample_output_dir"] + "/sra_data/PE/{accession}_R2.fastq.gz",
    message:
        "Compressing the raw fastq files {input.r1} and {input.r2}."
    threads: 8
    conda:
        "../envs/samtools.yaml"
    shell:
        "bgzip --stdout --threads {threads} {input.r1} 1> {output.r1}; "
        "bgzip --stdout --threads {threads} {input.r2} 1> {output.r2}"
