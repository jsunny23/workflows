## # Quality Check Standard
##
## This workflow runs a variety of quality checking software on any BAM file.
## It can be WGS, WES, or Transcriptome data. The results are aggregated and
## run through [MultiQC](https://multiqc.info/).
##
## ## LICENSING
## 
## #### MIT License
##
## Copyright 2019 St. Jude Children's Research Hospital
##
## Permission is hereby granted, free of charge, to any person obtaining a copy of this
## software and associated documentation files (the "Software"), to deal in the Software
## without restriction, including without limitation the rights to use, copy, modify, merge,
## publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
## to whom the Software is furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all copies or
## substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
## BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
## NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
## DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

version 1.0

import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/md5sum.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/picard.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/samtools.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/fastqc.wdl" as fqc
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/ngsderive.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/qualimap.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/fq.wdl"
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/fastq_screen.wdl" as fq_screen
import "https://raw.githubusercontent.com/stjudecloud/workflows/master/tools/multiqc.wdl" as mqc

workflow quality_check {
    input {
        File bam
        File bam_index
        File? gencode_gtf
        File? star_log
        String experiment
        String strand = ""
        File? fastq_screen_db
        String fastq_format = "sanger"
        Boolean paired_end = true
        Int max_retries = 1
    }

    parameter_meta {
        bam: "Input BAM format file to quality check"
        bam_index: "BAM index file corresponding to the input BAM"
        gencode_gtf: "GTF file provided by Gencode. **Required** for RNA-Seq data"
        star_log: "Log file generated by the RNA-Seq aligner STAR"
        experiment: "'WGS', 'WES', or 'RNA-Seq'"
        strand: "empty, 'Stranded-Reverse', 'Stranded-Forward', or 'Unstranded'. Only needed for RNA-Seq data. If missing, will be inferred"
        fastq_screen_db: "Database for FastQ Screen. Only for WGS and WES data. Can be generated using `make-qc-reference.wdl`. Must be named 'fastq-screen-db.tar.gz'"
        fastq_format: "Encoding format used for PHRED quality scores"
        paired_end: "Whether the data is paired end"
        max_retries: "Number of times to retry failed steps"
    }

    String provided_strand = strand

    call parse_input {
        input:
            input_experiment=experiment,
            input_gtf=gencode_gtf,
            input_strand=provided_strand,
            input_fq_db=fastq_screen_db,
            input_fq_format=fastq_format
    }

    call md5sum.compute_checksum { input: infile=bam, max_retries=max_retries }

    call picard.validate_bam { input: bam=bam, summary_mode=true, max_retries=max_retries }

    call samtools.flagstat as samtools_flagstat { input: bam=validate_bam.validated_bam, max_retries=max_retries }
    call fqc.fastqc { input: bam=validate_bam.validated_bam, max_retries=max_retries }
    call ngsderive.instrument as ngsderive_instrument { input: bam=validate_bam.validated_bam, max_retries=max_retries }
    call ngsderive.read_length as ngsderive_read_length { input: bam=validate_bam.validated_bam, bai=bam_index, max_retries=max_retries }
    call qualimap.bamqc as qualimap_bamqc { input: bam=validate_bam.validated_bam, max_retries=max_retries }

    if (experiment == "WGS" || experiment == "WES") {
        File fastq_screen_db_defined = select_first([fastq_screen_db, "No DB"])

        call samtools.subsample as samtools_subsample { input: bam=validate_bam.validated_bam, max_retries=max_retries }
        call picard.bam_to_fastq { input: bam=samtools_subsample.sampled_bam, max_retries=max_retries }
        call fq.fqlint { input: read1=bam_to_fastq.read1, read2=bam_to_fastq.read2, max_retries=max_retries }
        call fq_screen.fastq_screen as fastq_screen { input: read1=fqlint.validated_read1, read2=fqlint.validated_read2, db=fastq_screen_db_defined, format=fastq_format, max_retries=max_retries }
        
        call mqc.multiqc {
            input:
                sorted_bam=validate_bam.validated_bam,
                validate_sam_file=validate_bam.out,
                flagstat_file=samtools_flagstat.outfile,
                fastqc_files=fastqc.out_files,
                qualimap_bamqc=qualimap_bamqc.results,
                fastq_screen=fastq_screen.out_files,
                max_retries=max_retries
        }
    }
    if (experiment == "RNA-Seq") {
        File gencode_gtf_defined = select_first([gencode_gtf, "No GTF"])

        call ngsderive.infer_strand as ngsderive_strandedness { input: bam=validate_bam.validated_bam, bai=bam_index, gtf=gencode_gtf_defined, max_retries=max_retries }
        call qualimap.rnaseq as qualimap_rnaseq { input: bam=validate_bam.validated_bam, gencode_gtf=gencode_gtf_defined, provided_strand=provided_strand, inferred_strand=ngsderive_strandedness.strandedness, paired_end=paired_end, max_retries=max_retries }
        
        call mqc.multiqc as multiqc_rnaseq {
            input:
                sorted_bam=validate_bam.validated_bam,
                validate_sam_file=validate_bam.out,
                star_log=star_log,
                flagstat_file=samtools_flagstat.outfile,
                fastqc_files=fastqc.out_files,
                qualimap_bamqc=qualimap_bamqc.results,
                qualimap_rnaseq=qualimap_rnaseq.results,
                max_retries=max_retries
        }
    }

    output {
        File bam_checksum = compute_checksum.outfile
        File validate_sam_file = validate_bam.out
        File flagstat = samtools_flagstat.outfile
        Array[File] fastqc_results = fastqc.out_files
        File instrument_file = ngsderive_instrument.instrument_file
        File read_length_file = ngsderive_read_length.read_length_file
        File qualimap_bamqc_results = qualimap_bamqc.results
        Array[File]? fastq_screen_results = fastq_screen.out_files
        File? inferred_strandedness = ngsderive_strandedness.strandedness_file
        File? qualimap_rnaseq_results = qualimap_rnaseq.results
        File? multiqc_zip = multiqc.out
        File? multiqc_rnaseq_zip = multiqc_rnaseq.out
    }
}

task parse_input {
    input {
        String input_experiment
        File? input_gtf
        String input_strand
        File? input_fq_db
        String input_fq_format
    }

    Int disk_size = if defined(input_fq_db) then ceil(size(input_fq_db, "GiB") * 2) else 3
    
    String no_gtf = if defined(input_gtf) then "" else "true"

    command <<<
        EXITCODE=0
        if [ "~{input_experiment}" != "WGS" ] && [ "~{input_experiment}" != "WES" ] && [ "~{input_experiment}" != "RNA-Seq" ]; then
            >&2 echo "experiment input must be 'WGS', 'WES', or 'RNA-Seq'"
            EXITCODE=1
        fi

        if [ "~{input_experiment}" = "RNA-Seq" ] && [ "~{no_gtf}" = "true" ]; then
            >&2 echo "Must supply a Gencode GTF if experiment = 'RNA-Seq'"
            EXITCODE=1
        fi

        if [ -n "~{input_strand}" ] && [ "~{input_strand}" != "Stranded-Reverse" ] && [ "~{input_strand}" != "Stranded-Forward" ] && [ "~{input_strand}" != "Unstranded" ]; then
            >&2 echo "strand must be empty, 'Stranded-Reverse', 'Stranded-Forward', or 'Unstranded'"
            EXITCODE=1
        fi

        if { [ "~{input_experiment}" = "WGS" ] || [ "~{input_experiment}" = "WES" ]; } && [ "$(basename ~{input_fq_db})" != "fastq-screen-db.tar.gz" ]; then
            >&2 echo "FastQ Screen database (input \"fastq_screen_db\") must be archived and named fastq-screen-db.tar.gz"
            EXITCODE=1
        fi

        if [ -n "~{input_fq_format}" ] && [ "~{input_fq_format}" != "sanger" ] && [ "~{input_fq_format}" != "illunima1.3" ]; then
            >&2 echo "fastq_format must be empty, 'sanger', or 'illumina1.3'"
            EXITCODE=1
        fi
        exit $EXITCODE
    >>>

    runtime {
        disk: disk_size + " GB"
        docker: 'stjudecloud/util:1.0.0'
    }

    output {
        String input_check = "passed"
    }
}