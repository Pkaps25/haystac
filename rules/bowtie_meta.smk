#!/usr/bin/env python
# -*- coding: utf-8 -*-

__author__ = "Evangelos A. Dimopoulos, Evan K. Irving-Pease"
__copyright__ = "Copyright 2020, University of Oxford"
__email__ = "antonisdim41@gmail.com"
__license__ = "MIT"

import os
import pandas as pd

MIN_FRAG_LEN = 0
MAX_FRAG_LEN = 1000
META_ALN_MIN_SCORE_CONSTANT = -6

##### Target rules #####

from scripts.rip_utilities import get_total_paths, normalise_name


rule index_database_entrez:
    input:
        "database/{orgname}/{accession}.fasta.gz",
    log:
        "database/{orgname}/{accession}_index.log",
    output:
        expand("database/{orgname}/{accession}.{n}.bt2l", n=[1, 2, 3, 4], allow_missing=True),
        expand("database/{orgname}/{accession}.rev.{n}.bt2l", n=[1, 2], allow_missing=True),
    benchmark:
        repeat("benchmarks/index_database_{orgname}_{accession}.benchmark.txt", 1)
    message:
        "Preparing the bowtie2 index of genome {wildcards.accession} for taxon {wildcards.orgname}."
    shell:
        "bowtie2-build --large-index {input} database/{wildcards.orgname}/{wildcards.accession} &> {log}"


def get_idx_entrez(wildcards):
    """
    Get all the index paths for the taxa in our database from the entrez query.
    """
    if not config["with_entrez_query"]:
        return []

    pick_sequences = checkpoints.entrez_pick_sequences.get(query=wildcards.query)
    sequences = pd.read_csv(pick_sequences.output[0], sep="\t")

    if len(sequences) == 0:
        raise RuntimeError("The entrez pick sequences file is empty.")

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = (
            seq["species"].replace(" ", "_").replace("[", "").replace("]", ""),
            seq["GBSeq_accession-version"],
        )
        inputs.append(
            "database/{orgname}/{accession}.1.bt2l".format(
                orgname=orgname, accession=accession
            )
        )

    return inputs


def get_idx_ref_gen(wildcards):
    """
    Get all the index paths for the taxa in our database from the refseq rep and genbank.
    """
    if not config["with_refseq_rep"]:
        return []

    refseq_rep_prok = checkpoints.entrez_refseq_accessions.get(query=wildcards.query)

    refseq_genomes = pd.read_csv(refseq_rep_prok.output[0], sep="\t")
    genbank_genomes = pd.read_csv(refseq_rep_prok.output[1], sep="\t")
    refseq_plasmids = pd.read_csv(refseq_rep_prok.output[3], sep="\t")
    genbank_plasmids = pd.read_csv(refseq_rep_prok.output[4], sep="\t")

    sequences = pd.concat(
        [refseq_genomes, genbank_genomes, refseq_plasmids, genbank_plasmids]
    )

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = (
            seq["species"].replace(" ", "_").replace("[", "").replace("]", ""),
            seq["GBSeq_accession-version"],
        )
        inputs.append(
            "database/{orgname}/{accession}.1.bt2l".format(
                orgname=orgname, accession=accession
            )
        )

    return inputs


def get_idx_assembly(wildcards):
    """
    Get all the individual bam file paths for the taxa in our database.
    """
    if not config["with_refseq_rep"]:
        return []

    refseq_rep_prok = checkpoints.entrez_refseq_accessions.get(query=wildcards.query)

    assemblies = pd.read_csv(refseq_rep_prok.output[2], sep="\t")

    invalid_assemblies = checkpoints.entrez_invalid_assemblies.get(
        query=wildcards.query
    )
    invalid_assembly_sequences = pd.read_csv(invalid_assemblies.output[0], sep="\t")

    assemblies = assemblies[
        ~assemblies["GBSeq_accession-version"].isin(
            invalid_assembly_sequences["GBSeq_accession-version"]
        )
    ]

    sequences = assemblies

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = (
            seq["species"].replace(" ", "_").replace("[", "").replace("]", ""),
            seq["GBSeq_accession-version"],
        )
        inputs.append(
            "database/{orgname}/{accession}.1.bt2l".format(
                orgname=orgname, accession=accession
            )
        )

    return inputs


def get_idx_custom_seqs(wildcards):
    """
    Get all the individual bam file paths for the taxa in our database.
    """
    if not config["with_custom_sequences"]:
        return []

    custom_fasta_paths = pd.read_csv(
        config["custom_seq_file"],
        sep="\t",
        header=None,
        names=["species", "accession", "path"],
    )

    sequences = custom_fasta_paths

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = (
            seq["species"].replace(" ", "_").replace("[", "").replace("]", ""),
            seq["accession"],
        )
        inputs.append(
            "database/{orgname}/{accession}.1.bt2l".format(
                orgname=orgname, accession=accession
            )
        )

    return inputs


def get_idx_custom_acc(wildcards):
    """
    Get all the individual bam file paths for the taxa in our database.
    """
    if not config["with_custom_accessions"]:
        return []

    custom_accessions = pd.read_csv(
        config["custom_acc_file"], sep="\t", header=None, names=["species", "accession"]
    )

    sequences = custom_accessions

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = (
            seq["species"].replace(" ", "_").replace("[", "").replace("]", ""),
            seq["accession"],
        )
        inputs.append(
            "database/{orgname}/{accession}.1.bt2l".format(
                orgname=orgname, accession=accession
            )
        )

    return inputs


rule idx_database:
    input:
        get_idx_entrez,
        get_idx_ref_gen,
        get_idx_assembly,
        get_idx_custom_seqs,
        get_idx_custom_acc,
    log:
        "database/idx_database_{query}.log",
    output:
        "database/idx_database_{query}.done",
    message:
        "All the individual genome indices have been prepared."
    shell:
        "touch {output}"


def get_min_score(wildcards, input):
    """Get the min score dor the edit distance of the alignment."""
    return (
        round(float(open(input.readlen).read()) * float(config["mismatch_probability"]))
        * META_ALN_MIN_SCORE_CONSTANT
    )


rule align_taxon_single_end:
    input:
        fastq="{query}/fastq/SE/{sample}_mapq.fastq.gz", # bt2idx="database/{orgname}/{accession}.1.bt2l",
        db_idx="database/{orgname}/{accession}.1.bt2l",
        readlen="{query}/fastq/SE/{sample}_mapq.readlen",
    log:
        "{query}/sigma/{sample}/SE/{orgname}/{accession}.log",
    output:
        bam_file="{query}/sigma/{sample}/SE/{orgname}/{orgname}_{accession}.bam",
        bai_file="{query}/sigma/{sample}/SE/{orgname}/{orgname}_{accession}.bam.bai",
    benchmark:
        repeat(
            "benchmarks/align_taxon_single_end_{query}_{sample}_{orgname}_{accession}.benchmark.txt",
            1,
        )
    params:
        min_score=get_min_score,
        min_frag_length=MIN_FRAG_LEN,
        max_frag_length=MAX_FRAG_LEN,
    threads: config["bowtie2_treads"] # usually single threaded - the user can change it
    message:
        "Aligning file {input.fastq} against genome {wildcards.accession} of taxon {wildcards.orgname} "
        "for sample {wildcards.sample}, with {threads} thread(s). The output bam file is stored in {output.bam_file} "
        "and the log file can be found here {log}."
    shell:
        "( bowtie2 --time --no-unal --no-discordant --no-mixed --ignore-quals --mp 6,6 --np 6 "
        "   --score-min L,{params.min_score},0.0 --gbar 1000 -q --threads {threads} "
        '   -x database/"{wildcards.orgname}"/{wildcards.accession} '
        "   -I {params.min_frag_length} -X {params.max_frag_length} "
        "   -U {input.fastq} "
        "| samtools sort -O bam -o {output.bam_file} ) 2> {log}; "
        "samtools index {output.bam_file}"


rule align_taxon_paired_end:
    input:
        fastq_r1="{query}/fastq/PE/{sample}_R1_mapq.fastq.gz",
        fastq_r2="{query}/fastq/PE/{sample}_R2_mapq.fastq.gz", # bt2idx="database/{orgname}/{accession}.1.bt2l",
        db_idx="database/{orgname}/{accession}.1.bt2l",
        readlen="{query}/fastq/PE/{sample}_mapq_pair.readlen",
    log:
        "{query}/sigma/{sample}/PE/{orgname}/{accession}.log",
    output:
        bam_file="{query}/sigma/{sample}/PE/{orgname}/{orgname}_{accession}.bam",
        bai_file="{query}/sigma/{sample}/PE/{orgname}/{orgname}_{accession}.bam.bai",
    params:
        min_score=get_min_score,
        min_frag_length=MIN_FRAG_LEN,
        max_frag_length=MAX_FRAG_LEN,
    threads: config["bowtie2_treads"]
    message:
        "Aligning files {input.fastq_r1} and {input.fastq_r2} against genome {wildcards.accession} of "
        "taxon {wildcards.orgname} for sample {wildcards.sample}, with {threads} thread(s). "
        "The output bam file is stored in {output.bam_file} "
        "and the log file can be found here {log}."
    shell:
        "( bowtie2 --time --no-unal --no-discordant --no-mixed --ignore-quals --mp 6,6 --np 6 "
        "--score-min L,{params.min_score},0.0 --gbar 1000 -q --threads {threads} "
        '-x database/"{wildcards.orgname}"/{wildcards.accession} '
        "-I {params.min_frag_length} -X {params.max_frag_length} "
        "-1 {input.fastq_r1} -2 {input.fastq_r2} "
        "| samtools sort -O bam -o {output.bam_file} ) 2> {log} "
        "; samtools index {output.bam_file}"


# noinspection PyUnresolvedReferences
def get_bamfile_paths(wildcards):
    """
    Get all the individual bam file paths for the taxa in our database.
    """

    sequences = get_total_paths(
        wildcards,
        checkpoints,
        config["with_entrez_query"],
        config["with_refseq_rep"],
        config["with_custom_sequences"],
        config["with_custom_accessions"],
        config["specific_genera"],
    )

    inputs = []

    for key, seq in sequences.iterrows():
        orgname, accession = (
            normalise_name(seq["species"]),
            seq["GBSeq_accession-version"],
        )

        if config["SE"] or config["PE_ANCIENT"]:
            inputs.append(
                "{query}/sigma/{sample}/SE/{orgname}/{orgname}_{accession}.bam".format(
                    query=wildcards.query,
                    sample=wildcards.sample,
                    orgname=orgname,
                    accession=accession,
                )
            )
        elif config["PE_MODERN"]:
            inputs.append(
                "{query}/sigma/{sample}/PE/{orgname}/{orgname}_{accession}.bam".format(
                    query=wildcards.query,
                    sample=wildcards.sample,
                    orgname=orgname,
                    accession=accession,
                )
            )

    return inputs


rule all_alignments:
    input:
        get_bamfile_paths,
    output:
        "{query}/sigma/{sample}_alignments.done",
    benchmark:
        repeat("benchmarks/all_alignments_{query}_{sample}.benchmark.txt", 1)
    message:
        "All metagenomic alignments are done."
    shell:
        "touch {output}"
