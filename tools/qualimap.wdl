## Description:
##
## This WDL tool wraps the QualiMap tool (http://qualimap.bioinfo.cipf.es/).
## QualiMap computes metrics to facilitate evaluation of sequencing data. 

task bamqc {
    File bam
    Int ncpu
    String prefix = basename(bam, ".bam")

    command {
        qualimap bamqc -bam ${bam} \
            -outdir ${prefix}_qualimap_results \
            -nt ${ncpu} \
            --java-mem-size=6g
    }

    runtime {
        memory: "8 GB"
        disk: "80 GB"
        docker: 'stjudecloud/bioinformatics-base:bleeding-edge'
    }

    output {
        Array[File] out_files = glob("${prefix}_qualimap_results/*")
    }
}

task rnaseq {
    File bam
    File gencode_gtf
    String outdir = "qualimap_rnaseq"
    String strand = "strand-specific-reverse"
 
    command {
        qualimap rnaseq -bam ${bam} -gtf ${gencode_gtf} -outdir ${outdir} -oc qualimap_counts.txt -p ${strand} -pe --java-mem-size=12G
    }

    runtime {
        memory: "16 GB"
        disk: "80 GB"
        docker: 'stjudecloud/bioinformatics-base:bleeding-edge'
    }

    output {
        Array[File] out_files = glob("${outdir}/*")
    }
}
