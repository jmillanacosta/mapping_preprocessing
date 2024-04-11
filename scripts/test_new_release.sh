#!/bin/bash
#
# Script: test_new_release.sh
# Description: A script to test the data sources 
# Author: Javier Millan Acosta
# Date: April 2024

# Check if the source argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)"
    exit 1
fi

source="$1"

# Read config variables
source_config="datasources/$source/config"
if [ ! -f "$source_config" ]; then
    echo "Config file not found for $source"
    exit 1
fi
. "$source_config"

# Store common outputs from previous job in environment variables
echo "$DATE_NEW=$DATE_NEW" >> $GITHUB_ENV

# Create temp. folders to store the data in
mkdir -p "datasources/$source/data"

# Access the source to retrieve the latest release date
echo "Accessing the $source archive"
case $source in
    "chebi")
        echo "RELEASE_NUMBER=$RELEASE_NUMBER" >> $GITHUB_ENV
        echo "CURRENT_RELEASE_NUMBER=$CURRENT_RELEASE_NUMBER" >> $GITHUB_ENV
        url_release="https://ftp.ebi.ac.uk/pub/databases/chebi/archive/rel$RELEASE_NUMBER/SDF/"
        echo "URL_RELEASE=$url_release" >> $GITHUB_ENV
        wget "https://ftp.ebi.ac.uk/pub/databases/chebi/archive/rel${RELEASE_NUMBER}/SDF/ChEBI_complete_3star.sdf.gz"
        gunzip ChEBI_complete_3star.sdf.gz
        ls
        mkdir -p mapping_preprocessing/datasources/chebi/data
        inputFile="ChEBI_complete_3star.sdf" 
        mkdir new
        outputDir="datasources/chebi/recentData/"
        ;;
    "hgnc")
        echo "$COMPLETE_NEW=$COMPLETE_NEW" >> $GITHUB_ENV
        echo "$WITHDRAWN_NEW=$WITHDRAWN_NEW" >> $GITHUB_ENV
        wget "https://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/archive/quarterly/tsv/${WITHDRAWN_NEW}" \
             "https://ftp.ebi.ac.uk/pub/databases/genenames/hgnc/archive/quarterly/tsv/${COMPLETE_NEW}"
        mv "$WITHDRAWN_NEW" "$COMPLETE_NEW" datasources/hgnc/data
        ls -trlh datasources/hgnc/data
        sourceVersion=$DATE_NEW
        complete="datasources/hgnc/data/${COMPLETE_NEW}" 
        withdrawn="datasources/hgnc/data/${WITHDRAWN_NEW}" 
        ;;
    "hmdb")
        sudo apt-get install -y xml-twig-tools
        wget "http://www.hmdb.ca/system/downloads/current/hmdb_metabolites.zip"
        unzip hmdb_metabolites.zip
        mkdir -p hmdb
        mv hmdb_metabolites.xml hmdb
        cd hmdb
        xml_split -v -l 1 hmdb_metabolites.xml
        rm hmdb_metabolites.xml
        cd ../
        zip -r hmdb_metabolites_split.zip hmdb
        to_check_from_zenodo=$(grep -E '^to_check_from_zenodo=' datasources/hmdb/config | cut -d'=' -f2)
        inputFile=hmdb_metabolites_split.zip
        mkdir datasources/hmdb/recentData/
        outputDir="datasources/hmdb/recentData/"
        ;;
    "ncbi")
        wget "https://ftp.ncbi.nih.gov/gene/DATA/gene_info.gz" \
             "https://ftp.ncbi.nih.gov/gene/DATA/gene_history.gz"
        mv gene_info.gz gene_history.gz datasources/ncbi/data
        ls -trlh datasources/ncbi/data
        sourceVersion=$DATE_NEW
        gene_history="data/gene_history.gz" 
        gene_info="data/gene_info.gz" 
        ;;
    "uniprot")
        UNIPROT_SPROT_NEW="uniprot_sprot.fasta.gz"
        SEC_AC_NEW="sec_ac.txt"
        DELAC_SP_NEW="delac_sp.txt"
        wget "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/${UNIPROT_SPROT_NEW}" \
             "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/docs/${SEC_AC_NEW}" \
             "https://ftp.ebi.ac.uk/pub/databases/uniprot/current_release/knowledgebase/complete/docs/${DELAC_SP_NEW}"
        mv "$DELAC_SP_NEW" "$SEC_AC_NEW" "$UNIPROT_SPROT_NEW" datasources/uniprot/data
        ls -trlh datasources/uniprot/data
        sourceVersion=$DATE_NEW
        uniprot_sprot=$(echo datasources/uniprot/data/uniprot_sprot.fasta.gz)
        sec_ac=$(echo datasources/uniprot/data/sec_ac.txt)
        delac_sp=$(echo datasources/uniprot/data/delac_sp.txt)         
        ;;
    *)
        echo "Invalid source: $source"
        echo "Usage: $0 <source> (chebi | hgnc | hmdb | ncbi | uniprot)"
        exit 1
        ;;
esac

# Run processing programs and capture their exit code
if [ "$source" == "chebi" ]; then
    java -cp java/target/mapping_prerocessing-0.0.1-jar-with-dependencies.jar org.sec2pri.chebi_sdf "$inputFile" "$outputDir"
elif [ "$source" == "hgnc" ]; then
    Rscript r/src/hgnc.R $sourceVersion $withdrawn $complete
elif [ "$source" == "hmdb" ]; then
    java -cp java/target/mapping_prerocessing-0.0.1-jar-with-dependencies.jar org.sec2pri.hmdb_xml "$inputFile" "$outputDir"
elif [ "$source" == "ncbi" ]; then
    Rscript r/src/ncbi.R $sourceVersion $gene_history $gene_info
elif [ "$source" == "uniprot" ]; then
    Rscript r/src/uniprot.R $sourceVersion $uniprot_sprot $delac_sp $sec_ac
fi

# Check the exit status of the processing programs
if [ $? -eq 0 ]; then
    echo "Successful preprocessing of $source data."
    echo "FAILED=false" >> $GITHUB_ENV
else
    echo "Failed preprocessing of $source data."
    echo "FAILED=true" >> $GITHUB_ENV
fi
