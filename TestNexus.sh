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
#USER=$1
#PASSWD=$2
DEBUG_ARG=$1

ANT_ARGS=" "
ANT_OPTS="-Xmx512m"
START_DATE=`date '+%y%m%d-%H%M'`
BUILD_TYPE=SNAPSHOT

#Directories
ANT_HOME=/shared/common/apache-ant-1.7.0
HOME_DIR=/shared/rt/eclipselink
EXEC_DIR=${HOME_DIR}
DNLD_DIR=/home/data/httpd/download.eclipse.org/rt/eclipselink
JAVA_HOME=/shared/common/jdk-1.6.x86_64
LOG_DIR=${HOME_DIR}/logs
RELENG_REPO=${HOME_DIR}/eclipselink.releng
RUNTIME_REPO=${HOME_DIR}/eclipselink.runtime

#ANT Invokation Variables
BUILDFILE=${RUNTIME_REPO}/uploadToMaven.xml

#Global Variables
PUB_SCOPE_EXPECTED=0
PUB_SCOPE_COMPLETED=0
MASTER_BRANCH_VERSION=2.5

PATH=${JAVA_HOME}/bin:${ANT_HOME}/bin:/usr/bin:/usr/local/bin:${PATH}

# Export necessary global environment variables
export ANT_ARGS ANT_OPTS ANT_HOME HOME_DIR JAVA_HOME LOG_DIR PATH
#==========================
#   Functions Definitions
#
unset usage
usage() {
    echo "Usage: ${PROGNAME} USER PASSWD [debug]"
    echo "   USER      - user to publish artifacts to maven"
    echo "   PASSWD    - password for maven user"
    echo "   DEBUG_ARG - if defined, designates a run should be 'debug'."
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
            echo "Long-listing of '${src}/maven':"
            ls -l ${src}/maven
        fi

        #Invoke Antscript for Maven upload
        arguments="-Dbuild.deps.dir=${BldDepsDir} -Dcustom.tasks.lib=${RELENG_REPO}/ant_customizations.jar -Dversion.string=${version}.${qualifier}"
        arguments="${arguments} -Drelease.version=${version} -Dbuild.date=${blddate} -Dgit.hash=${githash} -Dbuild.type=${BUILD_TYPE} -Dbundle.dir=${src}/maven"
        #arguments="${arguments} -Drepository.username=${USER} -Drepository.userpass=${PASSWD}"

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


#==========================
#   Main Begins
#
#==========================
#   Validate run parameters
#if [ "${USER}" = "" ] ; then
#    usage
#    echo " "
#    echo "USER not specified! Exiting..."
#    exit 1
#fi
#if [ "${PASSWD}" = "" ] ; then
#    usage
#    echo " "
#    echo "PASSWD not specified! Exiting..."
#    exit 1
#fi
#  If anything is in DEBUG_ARG then do a dummy "DEBUG" run
#  run (Don't call ant, don't remove handoff, do report variable states
DEBUG=false
if [ -n "$DEBUG_ARG" ] ; then
    DEBUG=true
    echo "Debug is on!"
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

#==========================
#     Test for handoff
#        if not exit with minimal work done.
#==========================
curdir=`pwd`
cd $HOME_DIR
ERROR=false
handoff_cnt=0
for handoff in `ls handoff-file*.dat` ; do
    ERROR=false
    handoff_cnt=`expr ${handoff_cnt} + 1`
    if [ "$handoff_cnt" -gt "1" ] ; then
        echo " "
        echo " "
    fi
    echo "Detected handoff file:'${handoff}'. Process starting..."
    # Do stuff
    parseHandoff ${handoff}
    if [ "$PROC" = "build" ] ; then
           checkoutCurrentBranch ${RUNTIME_REPO} ${BRANCH_NM}

           echo "Preparing to upload to Sonatype OSS Repo. Setting Build to use 'uploadToNexus' script."
           BUILDFILE=${RUNTIME_REPO}/uploadToNexus.xml
           if [ -f ${BUILDFILE} ] ; then
#               BUILD_TYPE=M7
               echo "publishMavenRepo ${BUILD_ARCHIVE_LOC} ${BRANCH} ${BLDDATE} ${VERSION} ${QUALIFIER} ${GITHASH}"
               publishMavenRepo ${BUILD_ARCHIVE_LOC} ${BRANCH} ${BLDDATE} ${VERSION} ${QUALIFIER} ${GITHASH}
           else
               echo "Cannot find '${BUILDFILE}'. Aborting..."
           fi
    fi
    echo "   Finished."
done
echo "Publish complete."

