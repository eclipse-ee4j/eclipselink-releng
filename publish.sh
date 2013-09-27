# !/bin/sh
#****************************************************************************************
# Copyright (c) 2010, 2013 Oracle and/or its affiliates. All rights reserved.
# This program and the accompanying materials are made available under the
# terms of the Eclipse Public License v1.0 and Eclipse Distribution License v. 1.0
# which accompanies this distribution.
#
# The Eclipse Public License is available at http://www.eclipse.org/legal/epl-v10.html
# and the Eclipse Distribution License is available at
# http://www.eclipse.org/org/documents/edl-v10.php.
#
# Contributors:
#  - egwin - ?? ???ber 20?? - 2.? - Initial implementation
#  - egwin - 27 July 2012 - all - heavily modify for use with Hudson/Git process
#****************************************************************************************

#----------------------------------------------------------------------------------------
#    This script is designed to run from cron on the Eclipse foundation's build server
#       It tests for the existence of a completed build or test run
#       then initiates the publication of the results to the appropriate locations
#----------------------------------------------------------------------------------------

#==========================
#   Basic Env Setup
#

#Define common variables
THIS=$0
PROGNAME=`basename ${THIS}`
umask 0002
FLAG_ARG=$1
DEBUG_ARG=$2

ANT_ARGS=" "
ANT_OPTS="-Xms512m -Xmx1024m -XX:MaxPermSize=512m"
START_DATE=`date '+%y%m%d-%H%M'`
BUILD_TYPE=SNAPSHOT

#Directories
#ANT_HOME=/shared/common/apache-ant-1.7.0
#JAVA_HOME=/shared/common/jdk-1.6.x86_64
HOME_DIR=/shared/rt/eclipselink
EXEC_DIR=${HOME_DIR}
DNLD_DIR=/home/data/httpd/download.eclipse.org/rt/eclipselink
LOG_DIR=${HOME_DIR}/logs
RELENG_REPO=${HOME_DIR}/eclipselink.releng
RUNTIME_REPO=${HOME_DIR}/eclipselink.runtime

#ANT Invokation Variables
BUILDFILE=${RUNTIME_REPO}/uploadToMaven.xml

#Global Variables
PUB_SCOPE_EXPECTED=0
PUB_SCOPE_COMPLETED=0
MASTER_BRANCH_VERSION=2.6

#PATH=${JAVA_HOME}/bin:${ANT_HOME}/bin:/usr/bin:/usr/local/bin:${PATH}

# Export necessary global environment variables
export ANT_ARGS ANT_OPTS ANT_HOME HOME_DIR JAVA_HOME LOG_DIR PATH
#==========================
#   Functions Definitions
#
unset usage
usage() {
    echo "Usage: ${PROGNAME} [flag [debug]]"
    echo "   FLAG      - if defined as 'mvn' will publish to maven, otherwise designates a run should be 'debug'."
    echo "   DEBUG     - if FLAG is 'mvn' and DEBUG is defined, designates a 'mvn run' to be 'debug'."
}

unset createPath
createPath() {
    # Usage: createPath path
    path=$1

    if [ "${DEBUG}" = "true" ] ; then
        echo "createPath: Attempting to create '${path}' path."
    fi
    newdir=
    for directory in `echo ${path} | tr '/' ' '`
    do
        newdir=${newdir}/${directory}
        if [ ! -d "${newdir}" ] ; then
            if [ "${DEBUG}" = "true" ] ; then
                echo "createPath: Creating subdir: '${newdir}'"
            fi
            mkdir ${newdir}
            if [ $? -ne 0 ]
            then
                echo "   Error (createPath):  Creation of ${newdir} failed!"
                exit
            fi
        fi
    done
}

unset checkoutCurrentBranch
checkoutCurrentBranch() {
    local_repo=$1
    desired_branch=$2

    # make sure repo exists
    if [ ! -d ${local_repo} ] ; then
       echo "Error: Repo not found. exiting..."
       exit 1
    fi

    #Must run git commands from Git repo dir so, store current dir, and switch to repo
    current_dir=`pwd`
    cd ${local_repo}

    # switch to desired branch
    ${GIT_EXEC} checkout ${desired_branch}
    if [ "$?" = "0" ] ; then
       # parse status of repo for current branch
       current_branch=`${GIT_EXEC} status | grep -m1 "#" | cut -s -d' ' -f4`
       #if debug
       ## echo "Now on '${current_branch}' in '${local_repo}'"
       ## echo "Git checkout complete."
       if [ "${desired_branch}" = "${current_branch}" ] ; then
          # get latest on branch
          ##   has to occur after setting the correct banch because "git pull" only grabs changes on the active branch.
          ${GIT_EXEC} pull
       else
          echo "Error detected switching branches. exiting..."
          exit 1
       fi
    fi

    # reset to original dir
    cd $curdir
}

unset parseHandoff
parseHandoff() {
    # Usage: parseHandoff handoff_file
    handoff_file=$1
    handoff_error_string1="Error: Invalid handoff_file name: '${handoff_file}'"
    handoff_error_string2="                   Was expecting: 'handoff-file-<PROC>-<BRANCH_NM>-<QUALIFIER>.dat'"
    handoff_error_string3="                           where:"
    handoff_content_error1="Error: Invalid handoff_file contents: '`cat ${handoff_file}`'"
    handoff_content_error2="                       Was expecting: 'extract.loc=<BUILD_ARCHIVE_LOC> host=<HOST> maven.tag=<VERSION>-<MILESTONE>' "

    ## Parse handoff_file name for BRANCH_NM, QUALIFIER, and PROC (Procedure: Build/Test)
    BRANCH_NM=`echo ${handoff_file} | cut -s -d'-' -f4`
    if [ "${BRANCH_NM}" = "" ] ; then
        echo "BRANCH_NM ${handoff_error_string1}"
        echo "          ${handoff_error_string2}"
        BRANCH_NM_ERR=true
    else
        BRANCH_NM_ERR=false
    fi
    QUALIFIER=`echo ${handoff_file} | cut -s -d'-' -f5,6 | cut -d'.' -f1`
    if [ "${QUALIFIER}" = "" ] ; then
        echo "QUALIFIER ${handoff_error_string1}"
        echo "          ${handoff_error_string2}"
        QUALIFIER_ERR=true
    else
        QUALIFIER_ERR=false
    fi
    PROC=`echo ${handoff_file} | cut -s -d'-' -f3`
    if [ !  \( \( "${PROC}" = "test" \) -o \( "${PROC}" = "build" \) -o \( "${PROC}" = "tools" \) \) ] ; then
        echo "PROC ${handoff_error_string1}"
        echo "     ${handoff_error_string2}"
        echo "     ${handoff_error_string3} <PROC> = 'build','test', or 'tools'!"
        PROC_ERR=true
    else
        PROC_ERR=false
    fi
    ## Parse $QUALIFIER for build date value
    BLDDATE=`echo ${QUALIFIER} | cut -s -d'-' -f1 | cut -s -dv -f2`
    if [ "${BLDDATE}" = "" ] ; then
        echo "BLDDATE Error: There is something wrong with QUALIFIER. ('$QUALIFIER' should be vDATE-rREV)!"
        BLDDATE_ERR=true
    else
        BLDDATE_ERR=false
    fi
    ## Parse $QUALIFIER for Git Hash value
    GITHASH=`echo ${QUALIFIER} | cut -s -d'-' -f2`
    if [ "${GITHASH}" = "" ] ; then
        echo "GITHASH Error: There is something wrong with QUALIFIER. ('$QUALIFIER' should be vDATE-rREV)!"
        GITHASH_ERR=true
    else
        GITHASH_ERR=false
    fi
    ## Parse handoff_file contents for BUILD_ARCHIVE_LOC (Where files were stored), HOST and MAVEN_TAG
    BUILD_ARCHIVE_LOC=`cat ${handoff_file} | cut -d' ' -f1 | cut -d'=' -f2`
    if [ "${BUILD_ARCHIVE_LOC}" = "" ] ; then
        echo "BUILD_ARCHIVE_LOC ${handoff_content_error1}"
        echo "                  ${handoff_content_error2}"
        BUILD_ARCHIVE_LOC_ERR=true
    else
        BUILD_ARCHIVE_LOC_ERR_ERR=false
    fi
    HOST=`cat ${handoff_file} | cut -d' ' -f2 | cut -d'=' -f2`
    if [ "${HOST}" = "" ] ; then
        echo "HOST ${handoff_content_error1}"
        echo "     ${handoff_content_error2}"
        HOST_ERR=true
    else
        HOST_ERR=false
    fi
    MAVEN_TAG=`cat ${handoff_file} | cut -d' ' -f3 | cut -d'=' -f2`
    if [ "${MAVEN_TAG}" = "" ] ; then
        echo "MAVEN_TAG ${handoff_content_error1}"
        echo "          ${handoff_content_error2}"
        MAVEN_TAG_ERR=true
    else
        MAVEN_TAG_ERR=false
    fi
    ## Parse MAVEN_TAG for VERSION
    VERSION=`echo ${MAVEN_TAG} | cut -d'-' -f1`
    if [ "${VERSION}" = "" ] ; then
        echo "VERSION Error: Something wrong with MAVEN_TAG ('${MAVEN_TAG}' should be VERSION-MILESTONE)!"
        ## If parsing MAVEN_TAG failed, try parsing BUILD_ARCHIVE_LOC
        VERSION=`echo ${BUILD_ARCHIVE_LOC} | cut -d'/' -f6`
        if [ "${VERSION}" = "" ] ; then
            echo "VERSION (attempt 2) Error: Something wrong with BUILD_ARCHIVE_LOC '${BUILD_ARCHIVE_LOC}'!"
            VERSION_ERR=true
        else
            VERSION_ERR=false
        fi
    else
        VERSION_ERR=false
        ## Parse VERSION for BRANCH
        BRANCH=`echo ${VERSION} | cut -d'.' -f1-2`
        if [ "${BRANCH}" = "" ] ; then
            echo "BRANCH Error: Something wrong with VERSION ('${VERSION}' should be M.m.b)!"
        else
            BRANCH_ERR=false
        fi
    fi
    ## Parse handoff_file directory listing for TIMESTAMP
    TIMESTAMP=`ls -l --time-style=+%Y%m%d%H%M.%S ${handoff_file} | cut -d' ' -f6`
    if [ "${TIMESTAMP}" = "" ] ; then
        echo "TIMESTAMP error: Dir listing failed!"
        TIMESTAMP_ERR=true
    else
        TIMESTAMP_ERR=false
    fi
    if [ "${DEBUG}" = "true" ] ; then
        echo "parseHandoff: Parsed values:"
        echo "   BRANCH           = '${BRANCH}'"
        echo "   BRANCH_NM        = '${BRANCH_NM}'"
        echo "   QUALIFIER        = '${QUALIFIER}'"
        echo "   PROC             = '${PROC}'"
        echo "   BLDDATE          = '${BLDDATE}'"
        echo "   GITHASH          = '${GITHASH}'"
        echo "   BUILD_ARCHIVE_LOC= '${BUILD_ARCHIVE_LOC}'"
        echo "   HOST             = '${HOST}'"
        echo "   MAVEN_TAG        = '${MAVEN_TAG}'"
        echo "   VERSION          = '${VERSION}'"
        echo "   TIMESTAMP        = '${TIMESTAMP}'"
    fi
}

unset establishPublishScope
establishPublishScope() {
    # Usage: establishPublishScope src
    src=$1

    ## To test success set variables "PUB_SCOPE_EXPECTED" and "PUB_SCOPE_COMPLETED"
    ## compare at end and if match delete local build artifacts
    ## and handoff file.
    # 100 - artifacts to pub
    #  10 - p2 to pub
    #   1 - maven to pub (should be set if 100 = true, but only need eclipselink.jar and bundle.zip)

    #reset PUB_SCOPE_EXPECTED and PUB_SCOPE_COMPLETED for this handoff instance
    PUB_SCOPE_EXPECTED=0
    PUB_SCOPE_COMPLETED=0

    # search for zip files in src meaning need to publish artifacts
    srcZipCount=`ls ${src} | grep -c [.]zip$`
    if [ "${srcZipCount}" -gt 0 ] ; then
        PUB_SCOPE_EXPECTED=`expr ${PUB_SCOPE_EXPECTED} + 101`
        echo "Zip archives detected. Logging 'Archive publish' within scope."
    else
        echo "No zip archives detected. 'Archive publish' beyond scope."
    fi

    # search for p2repo dir, meaning need to publish P2
    # search for zip files in src meaning need to publish artifacts
    srcP2Count=`ls ${src} | grep -c p2repo`
    if [ \( ! "${srcP2Count}" = "0" \) ] ; then
        srcP2jarCount=`ls -r ${src}/p2repo/* | grep -c [.]jar$`
        if [ "${srcP2jarCount}" -gt 0 ] ; then
            PUB_SCOPE_EXPECTED=`expr ${PUB_SCOPE_EXPECTED} + 10`
            echo "Viable p2repo found. Logging 'p2 publish' within scope"
        else
            echo "p2repo dir found, but it is empty to publish. 'P2 publish' beyond scope."
        fi
    else
        echo "No p2repo found. 'P2 publish' beyond scope."
    fi
}

unset publishBuildArtifacts
publishBuildArtifacts() {
    # Usage: publishBuildArtifacts src dest version date timestamp
    src=$1
    dest=$2
    version=$3
    date=$4
    timestamp=$5
    qualifier=$6

    echo " "
    echo "Processing Build archives for publishing..."
    rootDest=${dest}/nightly

    #verify src, root dest, and needed variables exist before proceeding
    if [ \( -d "${src}" \) -a \( -d "${rootDest}" \) -a \( ! "${version}" = "" \) -a \( ! "${date}" = "" \) -a \( ! "${timestamp}" = "" \) ] ; then
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishBuildArtifacts: Required locations and data verified... proceeding..."
            echo "   src       = '${src}'"
            echo "   rootDest  = '${rootDest}'"
            echo "   version   = '${version}'"
            echo "   date      = '${date}'"
            echo "   timestamp = '${timestamp}'"
        fi
        
        #count number of jars exported
        srcJarCount=`ls ${src} | grep -c [.]jar$`
        #copy number of archives (zips) exported
        srcZipCount=`ls ${src} | grep -c [.]zip$`
        #track qualifier pattern in case multiple builds in one day (reverse order because sharedlib zip may be first and is non-conformant)
        srcQualified=`ls -r ${src} | grep -m1 [.]zip$ | cut -d'.' -f4`
        
        AlreadyProcessed=false
        if [ -d ${rootDest}/${version}/${date} ] ; then
            destJarCount=`ls ${downloadDest} | grep -c [.]jar$`
            destZipCount=`ls ${downloadDest}/*${srcQualified}* | grep -c [.]zip$`
            if [ "${DEBUG}" = "true" ] ; then
                echo "publishBuildArtifacts: ${destJarCount} jar(s) found pre-existing."
                echo "publishBuildArtifacts: ${destZipCount} zip(s) found pre-existing."
            fi
            if [ \( "${destJarCount}" -eq "${srcJarCount}" \) -a \( "${destZipCount}" -eq "${srcZipCount}" \) ] ; then
                AlreadyProcessed=true
            fi
        else
            #Mk download destination dir (dest/nightly/<version>/<date>)
            downloadDest=${rootDest}/${version}/${date}
            createPath ${downloadDest}
            
            #force <date> dir's date attribute to date of handoff
            touch -t${timestamp} ${downloadDest}
        fi
        
        if [ "${AlreadyProcessed}" = "false" ] ; then
            #copy number of jars exported, preserving date
            if [ "${srcJarCount}" -gt 0 ] ; then
                if [ "${DEBUG}" = "true" ] ; then
                    echo "publishBuildArtifacts: Copying ${srcJarCount} jar(s)"
                    echo "                       from: '${src}'"
                    echo "                         to: '${downloadDest}'"
                fi
                cp --preserve=timestamps ${src}/*.jar ${downloadDest}/.
            fi
            destJarCount=`ls ${downloadDest} | grep -c [.]jar$`
            if [ "${DEBUG}" = "true" ] ; then
                echo "publishBuildArtifacts: ${destJarCount} jar(s) copied."
            fi
    
            #copy number of archives (zips) exported, preserving date
            if [ "${srcZipCount}" -gt 0 ] ; then
                if [ "${DEBUG}" = "true" ] ; then
                    echo "publishBuildArtifacts: Copying ${srcZipCount} zip(s)"
                    echo "                       from: '${src}'"
                    echo "                         to: '${downloadDest}'"
                fi
                cp --preserve=timestamps ${src}/*.zip ${downloadDest}/.
            fi
            # check number of appropriately qualified destination files
            destZipCount=`ls ${downloadDest}/*${srcQualified}* | grep -c [.]zip$`
            if [ "${DEBUG}" = "true" ] ; then
                echo "publishBuildArtifacts: ${destZipCount} zips copied."
            fi
    
            #verify everything copied correctly
            if [ \( "${srcJarCount}" = "${destJarCount}" \) -a \( "${srcZipCount}" = "${destZipCount}" \) ] ; then
                echo "    Published ${destJarCount} jar(s) and ${destZipCount} zip(s) successfully."
                PUB_SCOPE_COMPLETED=`expr ${PUB_SCOPE_COMPLETED} + 100`
                NEW_WEB_ARTIFACTS=true
            else
                echo "    Published ${destJarCount} jar(s) and ${destZipCount} zip(s), but Src and Dest numbers don't match."
                echo "    Expected ${srcJarCount} jar(s) and ${srcZipCount} zip(s) to copy. Publish failed!"
                Error=true
            fi
        else
            echo "    Found ${destJarCount} jar(s) and ${destZipCount} zip(s) from build '${srcQualified}' pre-existing. Processing skipped."
            PUB_SCOPE_COMPLETED=`expr ${PUB_SCOPE_COMPLETED} + 100`
        fi
    else
        # Something is not right! skipping.."
        echo "    Required locations and data failed to verify... skipping Artifact publishing...."
        ERROR=true
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishBuildArtifacts: Required locations and data:"
            echo "   src       = '${src}'"
            echo "   rootDest  = '${rootDest}'"
            echo "   version   = '${version}'"
            echo "   date      = '${date}'"
            echo "   timestamp = '${timestamp}'"
        fi
    fi
}

unset publishP2Repo
publishP2Repo() {
    #Need handoff_loc, download location, version, qualifier
    # Usage: publishP2Repo src dest version qualifier
    src=$1
    dest=$2
    version=$3
    qualifier=$4

    echo " "
    echo "Preparing to publish P2 repository...."
    rootDest=${dest}/nightly-updates

    #verify src, root dest, and needed variables exist before proceeding
    if [ \( -d "${src}" \) -a \( -d "${rootDest}" \) -a \( ! "${version}" = "" \) -a \( ! "${qualifier}" = "" \) ] ; then
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishP2Repo: Required locations and data verified... proceeding..."
            echo "   src      = '${src}'"
            echo "   rootDest = '${rootDest}'"
            echo "   version  = '${version}'"
            echo "   qualifier= '${qualifier}'"
        fi

        #count number of repos exported (should be 0 or 1)
        #if not 0 and dir repo not already published, copy it preserving timestamps
        srcP2Count=`ls ${src} | grep -c p2repo`
        downloadDest=${rootDest}/${version}.${qualifier}
        if [ \( ! "${srcP2Count}" = "0" \) ] ; then
            srcP2jarCount=`ls -r ${src}/p2repo/* | grep -c [.]jar$`

            if [ \( ! -d ${downloadDest} \) ] ; then
                #Create download destination dir (dest/nightly-updates/<version>.<qualifier>)
                createPath ${downloadDest}

                if [ "${DEBUG}" = "true" ] ; then
                    echo "publishP2Repo: Copying ${srcP2Count} repo(s) (${srcP2jarCount} jars)"
                    echo "                       from: '${src}'"
                    echo "                         to: '${downloadDest}'"
                fi
                cp -r --preserve=timestamps ${src}/p2repo/* ${downloadDest}

                destP2jarCount=`ls -r ${downloadDest}/* | grep -c [.]jar$`
                if [ "${DEBUG}" = "true" ] ; then
                    echo "publishP2Repo: ${destP2jarCount} jars copied to repo."
                fi

                #verify everything copied correctly
                if [ "${destP2jarCount}" = "${srcP2jarCount}" ] ; then
                    echo "    Published ${destP2jarCount} of ${srcP2jarCount} jars to repo successfully."
                    PUB_SCOPE_COMPLETED=`expr ${PUB_SCOPE_COMPLETED} + 10`
                    NEW_P2=true
                else
                    echo "    Publish failed for P2 Repo. Only copied ${destP2jarCount} of ${srcP2jarCount} jars to repo."
                    ERROR=true
                    rm -r ${downloadDest}
                fi
            else
                destP2jarCount=`ls -r ${downloadDest}/* | grep -c [.]jar$`
                echo "   P2 repo already exists, ${destP2jarCount} of ${srcP2jarCount} jars published. Skipping..."
                PUB_SCOPE_COMPLETED=`expr ${PUB_SCOPE_COMPLETED} + 10`
            fi
        else
            echo "    No P2 repo to publish..."
            PUB_SCOPE_COMPLETED=`expr ${PUB_SCOPE_COMPLETED} + 10`
        fi
    else
        # Something is not right! skipping.."
        echo "    Required locations and data failed to verify... skipping Repo publishing...."
        ERROR=true
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishP2Repo: Required locations and data:"
            echo "   src      = '${src}'"
            echo "   rootDest = '${rootDest}'"
            echo "   version  = '${version}'"
            echo "   qualifier= '${qualifier}'"
        fi
    fi
}

unset publishMavenRepo
publishMavenRepo() {
    #Need handoff_loc, branch, date, version, qualifier, githash
    src=$1
    branch=$2
    blddate=$3
    version=$4
    qualifier=$5
    githash=$6

    echo " "
    echo "Preparing to publish Maven repository...."

    # Define SYSTEM variables needed
    BldDepsDir=${HOME_DIR}/bld_deps/${branch}
    if [ ! -d "${BldDepsDir}" ] ; then
        echo "${BldDepsDir} not found!"
    fi

    #verify src, root dest, and needed variables exist before proceeding
    if [ \( -d "${src}" \) -a \( -d "${BldDepsDir}" \) -a \( ! "${branch}" = "" \) -a \( ! "${blddate}" = "" \) -a \( ! "${version}" = "" \) -a \( ! "${qualifier}" = "" \) -a \( ! "${githash}" = "" \) ] ; then
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishMavenRepo: Required locations and data verified... proceeding..."
            echo "   src       = '${src}'"
            echo "   branch    = '${branch}'"
            echo "   blddate   = '${blddate}'"
            echo "   version   = '${version}'"
            echo "   qualifier = '${qualifier}'"
            echo "   githash   = '${githash}'"
        fi

        error_cnt=0

        # unzip necessary files to 'upload dir'/plugins
        ## start with nosql which isn't in older branches
        if [ ! "`ls ${src} | grep -c nosql`" = "0" ] ; then
            nosqlpluginzip=`ls ${src}/eclipselink-plugins-nosql*`
            if [ -f ${nosqlpluginzip} ] ; then
               unzip -o -q ${nosqlpluginzip} -d ${src}/maven
            fi
        else
            echo "No nosql installer zip found! Assuming older branch, skipping..."
        fi
        ## The rest should not have any issues
        srczip=`ls ${src}/eclipselink-src*`
        installzip=`ls ${src}/eclipselink-${version}*`
        pluginzip=`ls ${src}/eclipselink-plugins-${version}*`
        if [ "${DEBUG}" = "true" ] ; then
            echo "Expanding ${pluginzip}..."
        fi
        if [ -f ${pluginzip} ] ; then
           unzip -o -q ${pluginzip} -d ${src}/maven
        else
           echo "${pluginzip} not found!"
           error_cnt=`expr ${error_cnt} + 1`
        fi
        if [ "${DEBUG}" = "true" ] ; then
            echo "Prepping an eclipselink.jar..."
        fi
        if [ -f ${src}/eclipselink.jar ] ; then
            if [ "${DEBUG}" = "true" ] ; then
                echo "   Getting from exported files..."
            fi
            cp ${src}/eclipselink.jar ${src}/maven/.
        else
            if [ "${DEBUG}" = "true" ] ; then
                echo "    Expanding from ${installzip}..."
            fi
            if [ -f ${installzip} ] ; then
                unzip -o -j -q ${installzip} eclipselink/jlib/eclipselink.jar -d ${src}/maven
            else
                echo "${installzip} not found!"
                error_cnt=`expr ${error_cnt} + 1`
            fi
        fi
        if [ "${DEBUG}" = "true" ] ; then
            echo "Prepping a src.zip from ${srczip}..."
        fi
        if [ -f ${srczip} ] ; then
            cp ${srczip} ${src}/maven/eclipselink-src.zip
        else
            echo "${srczip} not found!"
            error_cnt=`expr ${error_cnt} + 1`
        fi
        if [ "${DEBUG}" = "true" ] ; then
            echo "Expanding javadoc from ${installzip}..."
        fi
        if [ -f ${installzip} ] ; then
            unzip -o -j -q ${installzip} eclipselink/*javadoc* -d ${src}/maven
        else
            echo "${installzip} not found!"
            error_cnt=`expr ${error_cnt} + 1`
        fi
        if [ "${DEBUG}" = "true" ] ; then
            echo "Long-listing of '${src}/maven':"
            ls -l ${src}/maven
        fi

        #Invoke Antscript for Maven upload
        arguments="-Dbuild.deps.dir=${BldDepsDir} -Dcustom.tasks.lib=${RELENG_REPO}/ant_customizations.jar -Dversion.string=${version}.${qualifier}"
        arguments="${arguments} -Drelease.version=${version} -Dbuild.date=${blddate} -Dgit.hash=${githash} -Dbuild.type=${BUILD_TYPE} -Dbundle.dir=${src}/maven"

        # Run Ant from ${exec_location} using ${buildfile} ${arguments}
        echo "ant ${BUILDFILE} ${arguments}"
        if [ -f ${BUILDFILE} ] ; then
            ant -f ${BUILDFILE} ${arguments}
            if [ "$?" = "0" ]
            then
                echo "Maven publish complete."
            else
                # if encountered error, increment error_cnt
                error_cnt=`expr ${error_cnt} + 1`
            fi
        else
            echo "${RUNTIME_REPO}/uploadToMaven.xml doesn't exist. Aborting ant run..."
            error_cnt=`expr ${error_cnt} + 1`
        fi
        if [ "$error_cnt" = "0" ]
        then
            # if successful, cleanup and set "COMPLETE"
            PUB_SCOPE_COMPLETED=`expr ${PUB_SCOPE_COMPLETED} + 1`
            if [ "${DEBUG}" = "true" ] ; then
                echo "Maven Publish completed. PUB_SCOPE_COMPLETED = '${PUB_SCOPE_COMPLETED}'"
            fi
        fi
    else
        # Something is not right! skipping.."
        echo "    Required locations and data failed to verify... skipping Maven publishing...."
        ERROR=true
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishMavenRepo: Required locations and data:"
            echo "   src       = '${src}'"
            echo "   branch    = '${branch}'"
            echo "   blddate   = '${blddate}'"
            echo "   version   = '${version}'"
            echo "   qualifier = '${qualifier}'"
            echo "   githash   = '${githash}'"
        fi
    fi
}

unset publishTestArtifacts
publishTestArtifacts() {
    # Usage: publishTestArtifacts src dest version date host
    src=$1
    dest=$2
    version=$3
    date=$4
    host=$5

    echo "Processing Test Results for publishing..."
    rootDest=${dest}/nightly

    #verify src, root dest, and needed variables exist before proceeding
    if [ \( -d "${src}" \) -a \( -d "${rootDest}" \) -a \( ! "${version}" = "" \) -a \( ! "${date}" = "" \) -a \( ! "${host}" = "" \) ] ; then
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishTestArtifacts: Required locations and data verified... proceeding..."
            echo "   src      = '${src}'"
            echo "   rootDest = '${rootDest}'"
            echo "   version  = '${version}'"
            echo "   date     = '${date}'"
            echo "   host     = '${host}'"
        fi

        #Mk download destination dir (dest/nightly/<version>/<date>)
        downloadDest=${rootDest}/${version}/${date}/${host}
        createPath ${downloadDest}

        #count number of pages (html) exported, and copy them preserving date
        srcHtmlCount=`ls ${src} | grep -c [.]html$`
        #track qualifier pattern in case multiple builds in one day
        srcQualified=`ls ${src} | grep -m1 [.]html$ | cut -d'.' -f4`
        if [ ! "${srcHtmlCount}" = "0" ] ; then
            if [ "${DEBUG}" = "true" ] ; then
                echo "publishTestArtifacts: Copying ${srcHtmlCount} html(s)"
                echo "                       from: '${src}'"
                echo "                         to: '${downloadDest}'"
            fi
            cp --preserve=timestamps ${src}/*.html ${downloadDest}/.
        fi
        # check number of appropriately qualified destination files
        destHtmlCount=`ls ${downloadDest}/*${srcQualified}* | grep -c [.]html$`
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishTestArtifacts: ${destHtmlCount} htmls copied."
        fi

        #verify everything copied correctly
        if [ "${srcHtmlCount}" = "${destHtmlCount}" ] ; then
            echo "    Published ${destHtmlCount} html(s) successfully."
            # can clean up.
            rm -r ${src}
            NEW_WEB_ARTIFACTS=true
        else
            echo "    Publish failed for Test Results."
            ERROR=true
        fi
    else
        # Something is not right! skipping.."
        echo "    Required locations and data failed to verify... skipping Test Artifact publishing...."
        ERROR=true
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishTestArtifacts: Required locations and data:"
            echo "   src       = '${src}'"
            echo "   rootDest  = '${rootDest}'"
            echo "   version   = '${version}'"
            echo "   date      = '${date}'"
            echo "   timestamp = '${timestamp}'"
        fi
    fi
}

unset publishToolsArtifacts
publishToolsArtifacts() {
    # Usage: publishToolsArtifacts src dest version date host
    src=$1
    dest=$2
    version=$3
    date=$4

    echo "Processing Tools Results for publishing..."
    rootDest=${dest}/nightly

    #verify src, root dest, and needed variables exist before proceeding
    if [ \( -d "${src}" \) -a \( -d "${rootDest}" \) -a \( ! "${version}" = "" \) -a \( ! "${date}" = "" \) ] ; then
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishTestArtifacts: Required locations and data verified... proceeding..."
            echo "   src      = '${src}'"
            echo "   rootDest = '${rootDest}'"
            echo "   version  = '${version}'"
            echo "   date     = '${date}'"
        fi

        #Mk download destination dir (dest/nightly/<version>/<date>)
        downloadDest=${rootDest}/${version}/${date}
        createPath ${downloadDest}

        #count number of pages (html) exported, and copy them preserving date
        srcZipCount=`ls ${src} | grep -c [.]zip$`
        #track qualifier pattern in case multiple builds in one day
        srcQualified=`ls ${src} | grep -m1 [.]zip$ | cut -d'.' -f4`
        if [ ! "${srcZipCount}" = "0" ] ; then
            if [ "${DEBUG}" = "true" ] ; then
                echo "publishToolsArtifacts: Copying ${srcZipCount} zip(s)"
                echo "                       from: '${src}'"
                echo "                         to: '${downloadDest}'"
            fi
            cp --preserve=timestamps ${src}/*.zip ${downloadDest}/.
        fi
        # check number of appropriately qualified destination files
        destZipCount=`ls ${downloadDest}/*${srcQualified}* | grep -c [.]zip$`
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishToolsArtifacts: ${destZipCount} htmls copied."
        fi

        #verify everything copied correctly
        if [ "${srcZipCount}" = "${destZipCount}" ] ; then
            echo "    Published ${destZipCount} zip(s) successfully."
            # can clean up.
            rm -r ${src}
            NEW_WEB_ARTIFACTS=true
        else
            echo "    Publish failed for Test Results."
            ERROR=true
        fi
    else
        # Something is not right! skipping.."
        echo "    Required locations and data failed to verify... skipping Test Artifact publishing...."
        ERROR=true
        if [ "${DEBUG}" = "true" ] ; then
            echo "publishToolsArtifacts: Required locations and data:"
            echo "   src       = '${src}'"
            echo "   rootDest  = '${rootDest}'"
            echo "   version   = '${version}'"
            echo "   date      = '${date}'"
            echo "   timestamp = '${timestamp}'"
        fi
    fi
}

#==========================
#   Main Begins
#
#==========================
#  Test FLAG_ARG and DEBUG_ARG to determine run properties (MVN run and/or "DEBUG" run)
#  DEBUG run: (Don't call ant, don't remove handoff, do report variable states
DEBUG=false
MVN=false
if [ -n "$FLAG_ARG" ] ; then
    if [ "$FLAG_ARG" = "mvn" ] ; then
        MVN=true
        echo "Maven publish is on!"
        if [ -n "$DEBUG_ARG" ] ; then
            DEBUG=true
            echo "Debug is on!"
        fi
    else
        DEBUG=true
        echo "Debug is on!"
    fi
else
    echo "MVN and DEBUG are off."
fi

#==========================
#     Define Environment
#
#==========================
GIT_EXEC=/usr/local/bin/git
if [ ! -x ${GIT_EXEC} ] ; then
    echo "Cannot find Git executable using default value '$GIT_EXEC'. Attempting Autofind..."
    GIT_EXEC=`which git`
    if [ $? -ne 0 ] ; then
        echo "Error: Unable to find GIT executable! Git functionality disabled."
        GIT_EXEC=false
        exit 1
    else
        echo "Found: ${GIT_EXEC}"
    fi
else
    echo "Found: ${GIT_EXEC}"
fi

# Check for M2_HOME (only set in bashrc: if not set running from cron, and load)
if [ ! -x ${M2_HOME}/bin/mvn ] ; then
    echo "Cannot find Maven executable using default value '${M2_HOME}/bin/mvn'. Loading .bashrc..."
    source ${HOME}/.bashrc
    if [ $? -ne 0 ] ; then
        echo "Error: Unable to load ${HOME}/.bashrc... exiting"
        exit 1
    else
        if [ ! -x ${M2_HOME}/bin/mvn ] ; then
            echo "Still Cannot find Maven executable using default value '${M2_HOME}/bin/mvn'. exiting..."
            exit 1
        else
            echo "Found: ${M2_HOME}/bin/mvn"
        fi
    fi
else
    echo "Found: ${M2_HOME}/bin/mvn"
fi

#==========================
#     Test for handoff
#        if not exit with minimal work done.
#==========================
curdir=`pwd`
NEW_RESULTS=false
NEW_P2=false
NEW_WEB_ARTIFACTS=false
ERROR=false
handoff_cnt=0

echo "=========================================== "
cd $HOME_DIR
for handoff in `ls handoff-file*.dat` ; do
    ERROR=false
    cd $HOME_DIR
    handoff_cnt=`expr ${handoff_cnt} + 1`
    if [ "$handoff_cnt" -gt "1" ] ; then
        echo " "
        echo " "
    fi
    echo "Detected handoff file:'${handoff}'. Process starting..."
    # Do stuff
    parseHandoff ${handoff}
    if [ "$PROC" = "build" ] ; then
       establishPublishScope ${BUILD_ARCHIVE_LOC}
       if [ "${PUB_SCOPE_EXPECTED}" -ge 100 ] ; then
           publishBuildArtifacts ${BUILD_ARCHIVE_LOC} ${DNLD_DIR} ${VERSION} ${BLDDATE} ${TIMESTAMP}
       fi
       if [ "${PUB_SCOPE_EXPECTED}" -ge 10 ] ; then
           publishP2Repo ${BUILD_ARCHIVE_LOC} ${DNLD_DIR} ${VERSION} ${QUALIFIER}
       fi
       if [ "${MVN}" = "true" ] ; then
           checkoutCurrentBranch ${RUNTIME_REPO} ${BRANCH_NM}
           echo "Preparing to upload to EclipseLink Maven Repo. Setting Build to use 'uploadToMaven' script."
           BUILDFILE=${RUNTIME_REPO}/uploadToMaven.xml
           if [ -f ${BUILDFILE} ] ; then
               echo "publishMavenRepo ${BUILD_ARCHIVE_LOC} ${BRANCH} ${BLDDATE} ${VERSION} ${QUALIFIER} ${GITHASH}"
               publishMavenRepo ${BUILD_ARCHIVE_LOC} ${BRANCH} ${BLDDATE} ${VERSION} ${QUALIFIER} ${GITHASH}
           else
               echo "Cannot find '${BUILDFILE}'. Aborting..."
           fi

           echo "Preparing to upload to Sonatype OSS Repo. Setting Build to use 'uploadToNexus' script."
           BUILDFILE=${RUNTIME_REPO}/uploadToNexus.xml
           if [ -f ${BUILDFILE} ] ; then
               echo "publishMavenRepo ${BUILD_ARCHIVE_LOC} ${BRANCH} ${BLDDATE} ${VERSION} ${QUALIFIER} ${GITHASH}"
               publishMavenRepo ${BUILD_ARCHIVE_LOC} ${BRANCH} ${BLDDATE} ${VERSION} ${QUALIFIER} ${GITHASH}
           else
               echo "Cannot find '${BUILDFILE}'. Aborting..."
           fi
           # With two maven pushes Completed should be 1 higher than expected, so adjust before compare
           PUB_SCOPE_COMPLETED=`expr ${PUB_SCOPE_COMPLETED} - 1`

       fi
       if [ "${PUB_SCOPE_EXPECTED}" = "${PUB_SCOPE_COMPLETED}" ] ; then
           if [ "${DEBUG}" = "true" ] ; then
               echo "PUB_SCOPE_EXPECTED  = '${PUB_SCOPE_EXPECTED}'"
               echo "PUB_SCOPE_COMPLETED = '${PUB_SCOPE_COMPLETED}'"
           fi
           echo "Success: now deleting '${handoff}'"
           echo "TODO: also should delete '${BUILD_ARCHIVE_LOC}' but need to make sure tests export to different area first"
           rm ${HOME_DIR}/${handoff}
           NEW_RESULTS=true
       else
           if [ "${DEBUG}" = "true" ] ; then
               echo "PUB_SCOPE_EXPECTED  = '${PUB_SCOPE_EXPECTED}'"
               echo "PUB_SCOPE_COMPLETED = '${PUB_SCOPE_COMPLETED}'"
           fi
           echo "Full processing failed: Cannot remove '${handoff}' and '${BUILD_ARCHIVE_LOC}'"
           echo "    Deletion aborted..."
       fi
    else
       if [ "$PROC" = "test" ] ; then
          publishTestArtifacts ${BUILD_ARCHIVE_LOC} ${DNLD_DIR} ${VERSION} ${BLDDATE} ${HOST}
          # Can combine when build publish complete.
          if [ "${ERROR}" = "false" ] ; then
              echo "Processing of '${handoff}' complete."
              # remove handoff
              echo "   Removing '${handoff}'."
              rm ${HOME_DIR}/${handoff}
          else
              # Report error
              echo "Error processing of '${handoff}'."
              echo "    Deletion aborted..."
          fi
       else
          if [ "$PROC" = "tools" ] ; then
             echo "TOOLS detected!"
             publishToolsArtifacts ${BUILD_ARCHIVE_LOC} ${DNLD_DIR} ${VERSION} ${BLDDATE}
             # Can combine when build publish complete.
             if [ "${ERROR}" = "false" ] ; then
                 echo "Processing of '${handoff}' complete."
                 # remove handoff
                 echo "   Removing '${handoff}'."
                 rm ${HOME_DIR}/${handoff}
             else
                 # Report error
                 echo "Error processing of '${handoff}'."
                 echo "    Deletion aborted..."
             fi
          else
             echo "Unknown handoff type: '$PROC'"
          fi
       fi
    fi
    echo "   Finished."
done
echo "Completed processing of all (${handoff_cnt}) handoff files."
if [ "${NEW_RESULTS}" = "true" ] ; then
    # clean up old artifacts
    echo "Could now run './${RELENG_REPO}/cleanNightly.sh' to remove old artifacts."
    echo "   but will need to accumulate branches effected in this run before can know which ones to clean."
    # regen web
fi
if [ "${NEW_WEB_ARTIFACTS}" = "true" ] ; then
    if [ -f ${RELENG_REPO}/buildNightlyList-cron.sh ] ; then
        echo "Now running '${RELENG_REPO}/buildNightlyList-cron.sh' to regenerate nightly download page."
        ${RELENG_REPO}/buildNightlyList-cron.sh
    else
        echo "cannot find '${RELENG_REPO}/buildNightlyList-cron.sh' to run."
    fi
fi
if [ "${NEW_P2}" = "true" ] ; then
    # regen P2 composite
    if [ -f ${RELENG_REPO}/buildCompositeP2.sh ] ; then
        echo "Now running '${RELENG_REPO}/buildCompositeP2.sh nightly' to rebuild composite metadata for the nightly P2 repo."
        ${RELENG_REPO}/buildCompositeP2.sh nightly
    else
        echo "cannot find '${RELENG_REPO}/buildCompositeP2.sh' to run."
    fi
fi
echo "Publish complete."

