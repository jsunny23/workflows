## Description:
##
## This WDL tool includes custom scripts to parse and validate QC output.  

version 1.0

task parse_validate_bam {
    input {
        String in
        Boolean strict = true
    }
 
    command {
        if [ "${strict}" == "true" ]
        then 
           if [ $(echo "${in}" | grep -c "ERROR") -gt 0 ]
           then 
              echo "Errors detected by Picard ValidateSamFile" > /dev/stderr
              exit -1 
           fi
        elif [ $(echo "${in}" | grep -Ec "ERROR|WARNING") -gt 0 ]
        then
              echo "Errors detected by Picard ValidateSamFile" > /dev/stderr
              exit -1 
        fi
    }

    runtime {
        docker: 'stjudecloud/bioinformatics-base:bleeding-edge'
    }
}

task parse_infer_experiment {
    input {
        String in
    }

    command { 
        if [ $(echo "${in}" | grep -c 'PairEnd') -gt 0 ]
        then
            if (( $(echo "$(echo "${in}" | tail -n 1 | sed  's/^.*: //') > 0.5" | bc -l ) ))
            then
               echo 'strand-specific-reverse' > stdout.txt
            elif (( $(echo "$(echo "${in}" | tail -n 2 | head -n 1 | sed  's/^.*: //') > 0.5" | bc -l ) ))
            then 
               echo 'strand-specific-forward' > stdout.txt
            else
               echo 'non-strand-specific' > stdout.txt
            fi
        elif [ $(echo "${in}" | grep -c 'SingleEnd') -gt 0 ]
        then 
            if (( $(echo "$(echo "${in}" | tail -n 1 | sed  's/^.*: //') > 0.5" | bc -l ) ))
            then
               echo 'strand-specific-reverse' > stdout.txt
            elif (( $(echo "$(echo "${in}" | tail -n 2 | head -n 1 | sed  's/^.*: //') > 0.5" | bc -l ) ))
            then 
               echo 'strand-specific-forward' > stdout.txt
            else
               echo 'non-strand-specific' > stdout.txt
            fi
        else
           echo "infer_experiment failed to determine type" > /dev/stderr
           exit -1 
        fi
    }

    runtime {
        docker: 'stjudecloud/bioinformatics-base:bleeding-edge'
    }

    output {
        String out = read_string("stdout.txt")
    }

}
