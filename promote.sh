# !/bin/sh
#****************************************************************************************
# Copyright (c) 2012 Oracle and/or its affiliates. All rights reserved.
# This program and the accompanying materials are made available under the
# terms of the Eclipse Public License v1.0 and Eclipse Distribution License v. 1.0
# which accompanies this distribution.
#
# The Eclipse Public License is available at http://www.eclipse.org/legal/epl-v10.html
# and the Eclipse Distribution License is available at
# http://www.eclipse.org/org/documents/edl-v10.php.
#
# Contributors:
#  - egwin - 13 September 2012 - Initial implementation
#****************************************************************************************

#----------------------------------------------------------------------------------------
#    This script is designed to be run interactively to promote an existing published
#    build to a milestone, or a Milestone build to a release. It expects to be run from
#    the 'build.eclipse.com' server.
#----------------------------------------------------------------------------------------

#==========================
#   Basic Env Setup
#

#Define common variables
THIS=$0
PROGNAME=`basename ${THIS}`
CUR_DIR=`dirname ${THIS}`
umask 0002
BUILD=$1
MILESTONE=$2
BRANCH_NM=$3
ARG4=$4

ANT_ARGS=" "
ANT_OPTS="-Xmx512m"
START_DATE=`date '+%y%m%d-%H%M'`

#Directories
ANT_HOME=/shared/common/apache-ant-1.7.0
HOME_DIR=/shared/rt/eclipselink
EXEC_DIR=${HOME_DIR}
DNLD_DIR=/home/data/httpd/download.eclipse.org/rt/eclipselink
JAVA_HOME=/shared/common/jdk-1.6.x86_64
LOG_DIR=${HOME_DIR}/logs
RELENG_REPO=${HOME_DIR}/eclipselink.releng
RUNTIME_REPO=${HOME_DIR}/eclipselink.runtime

#Files
BUILDFILE=${RUNTIME_REPO}/autobuild.xml

#Global Variables
RELEASE=false
ANT_TARGET=build-milestone

#  If anything is in ARG4 then do a dummy "DEBUG" run
#  (Do not call ant, do not modify or create files, do report variable states)
DEBUG=false

PATH=${JAVA_HOME}/bin:${ANT_HOME}/bin:/usr/bin:/usr/local/bin:${PATH}

# Export necessary global environment variables
export ANT_ARGS ANT_OPTS ANT_HOME HOME_DIR JAVA_HOME LOG_DIR PATH
#==========================
#   Functions Definitions
#
unset usage
usage() {
    echo "Usage: ./promote.sh (BUILD |'release') MILESTONE BRANCH_NM [debug]"
    echo "  BUILD     - full build identifier, or 'release' (example: 2.4.1.v201209013-98ef31a). Used to generate branch,"
    echo "              version, date and hash info needed. If 'release', tells promote to release the specified"
    echo "              MILESTONE."
    echo "  MILESTONE - a milestone (exampe: M4) to promote the specified build to. Also used in dir storage, and maven."
    echo "              storage, and Maven publishing."
    echo "  BRANCH_NM - The git branchname for the branch the build was based upon (Example: master, 2.4, 2.3, etc.)"
    echo "  ARG4      - if defined, designates a run should be 'debug'."
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
                echo "   createPath:  Error, creation of ${newdir} failed!"
                exit
            fi
        fi
    done
}

unset genSafeTmpDir
genSafeTmpDir() {
    tmp=${TMPDIR-/tmp}
    tmp=$tmp/somedir.$RANDOM.$RANDOM.$RANDOM.$$
    (umask 077 && mkdir $tmp) || {
      echo "Could not create temporary directory! Exiting." 1>&2
      exit 1
    }
    echo "results stored in: '${tmp}'"
}

unset parseBuild
parseBuild() {
    build=$1

    echo "- parseBuild -"

    # cut parameters: -s: only print if delimeter exists in input; -d delimeter; -f field(s) to print
    BRANCH=`echo ${build} | cut -s -d'.' -f1-2`
    if [ "${BRANCH}" = "" ] ; then
        usage
        echo "BRANCH Error: There is something wrong with BUILD. ('$build' should be VERSION.QUALIFIER)!"
        echo "              VERSION should be in the 3 part OSGi standard - Major.Minor.patch"
        echo " "
        exit 2
    fi

    VERSION=`echo ${build} | cut -s -d'.' -f1-3`
    if [ "${VERSION}" = "" ] ; then
        usage
        echo "VERSION Error: There is something wrong with BUILD. ('$build' should be VERSION.QUALIFIER)!"
        echo "               VERSION should be in the 3 part OSGi standard - Major.Minor.patch"
        echo " "
        exit 2
    fi

    QUALIFIER=`echo ${build} | cut -s -d'.' -f4`
    if [ "${QUALIFIER}" = "" ] ; then
        usage
        echo "QUALIFIER Error: There is something wrong with BUILD. ('$build' should be VERSION.QUALIFIER)!"
        echo "                 QUALIFIER should be in the form: vDATE-HASH where DATE is YYYYMMDD"
        echo " "
        exit 2
    fi

    # assign value of first field delimited by '-' (only use values containing '-' (-s)), with 'v' stripped, to DATE
    BLD_DATE=`echo ${QUALIFIER} | cut -s -d'-' -f1 | cut -s -d'v' -f2`
    if [ "${BLD_DATE}" = "" ] ; then
        usage
        echo "BLD_DATE Error: There is something wrong with QUALIFIER!"
        echo "                '$qualifier' should be in the form:"
        echo "                     vDATE-HASH where DATE is YYYYMMDD"
        echo " "
        exit 2
    fi

    # assign value of 2nd field delimited by '-' (only use values containing '-' (-s)), to HASH
    GIT_HASH=`echo ${QUALIFIER} | cut -s -d'-' -f2`
    if [ "${GIT_HASH}" = "" ] ; then
        usage
        echo "GIT_HASH Error: There is something wrong with QUALIFIER!"
        echo "                '$qualifier' should be in the form:"
        echo "                     vDATE-HASH where DATE is YYYYMMDD"
        echo " "
        exit 2
    fi

    if [ "$DEBUG" = "true" ] ; then
        echo "build    ='$build'"
        echo "BRANCH   ='$BRANCH'"
        echo "VERSION  ='$VERSION'"
        echo "QUALIFIER='$QUALIFIER'"
        echo "BLD_DATE ='$BLD_DATE'"
        echo "GIT_HASH ='$GIT_HASH'"
    fi
}

# TODO: NEED branch to verify instead of branch_NM, but need branch_NM to interact with Git
unset validateBuild
validateBuild() {
    echo "- validateBuild -"

    if [ -d ${DNLD_DIR}/nightly/${VERSION}/${BLD_DATE} ] ; then
        echo "Valid build dir: '${DNLD_DIR}/nightly/${VERSION}/${BLD_DATE}'"
        if [ -e ${DNLD_DIR}/nightly/${VERSION}/${BLD_DATE}/eclipselink-${VERSION}.${QUALIFIER}.zip ] ; then
            echo "Valid build: '${DNLD_DIR}/nightly/${VERSION}/${BLD_DATE}/eclipselink-${VERSION}.${QUALIFIER}.zip' found."
        else
            echo "Invalid build: '${DNLD_DIR}/nightly/${VERSION}/${BLD_DATE}/eclipselink-${VERSION}.${QUALIFIER}.zip' not found."
            echo "Valid builds are:"
            ls ${DNLD_DIR}/nightly/${VERSION}/${BLD_DATE}/eclipselink-${VERSION}*.zip
            exit 1
        fi
    else
            echo "Invalid build dir: '${DNLD_DIR}/nightly/${VERSION}/${BLD_DATE}'"
            echo "Valid build dates are:"
            ls ${DNLD_DIR}/nightly/${VERSION}
            exit 1
   fi
   #cd $curdir

}

# TODO: again NEED branch to verify instead of branch_NM, but need branch_NM to interact with Git
unset validateMilestone
validateMilestone() {
    milestone=$1
    echo "- validateMilestone -"

    # TODO: Verify ${milestone} is 'release', or starts with M# or RC#
    if [ -d ${DNLD_DIR}/milestones/${VERSION}/${milestone} ] ; then
        echo "Milestone dir: '${DNLD_DIR}/milestones/${VERSION}/${milestone}' already exists."
        if [ -e ${DNLD_DIR}/milestones/${VERSION}/${milestone}/eclipselink-${VERSION}.${QUALIFIER}.zip ] ; then
            echo "     Milestone ${milestone} Build: '${DNLD_DIR}/milestones/${VERSION}/${milestone}/eclipselink-${VERSION}.${QUALIFIER}.zip' already promoted."
        else
            promotedBuild=`ls ${DNLD_DIR}/milestones/${VERSION}/${milestone}/eclipselink-${VERSION}*.zip`
            echo "     Milestone ${milestone} Build: '${promotedBuild}' found."
        fi
        echo "     You should either choose another Milestone number, or clean previous promote (if partial) before running again."
        exit 1
    else
        echo "Milestone dir: '${DNLD_DIR}/milestone/${VERSION}/${milestone}' not preexisting."
        echo "Continuing..."
    fi

}

#TODO Must have Git validation and setup completed first
unset callAnt
callAnt() {
    #Need milestine branch, version, qualifier, date, githash
    milestone=$1
    branch=$2
    branch_nm=$3
    version=$4
    qualifier=$5
    blddate=$6
    githash=$7

    echo " "
    echo "- callAnt -"

    # Define SYSTEM variables needed
    BldDepsDir=${HOME_DIR}/bld_deps/${branch}    # Needed for Eclipse dependencies when publishing/promoting
    if [ ! -d "${BldDepsDir}" ] ; then
        echo "${BldDepsDir} not found!"
    fi
    if [ ! -d "${RELENG_REPO}" ] ; then
        echo "${RELENG_REPO} not found!"
    fi

    #verify src, root dest, and needed variables exist before proceeding
    if [ \( ! "${milestone}" = "" \) -a \( ! "${branch}" = "" \) -a \( ! "${blddate}" = "" \) -a \( ! "${version}" = "" \) -a \( ! "${qualifier}" = "" \) ] ; then
        echo "Preparing to promote ${milestone} for ${version}...."
        if [ "${DEBUG}" = "true" ] ; then
            echo "callAnt: Required data verified... proceeding..."
            echo "   milestone = '${milestone}'"
            echo "   branch    = '${branch}'"
            echo "   blddate   = '${blddate}'"
            echo "   version   = '${version}'"
            echo "   qualifier = '${qualifier}'"
            echo "   githash   = '${githash}'"
        fi

        error_cnt=0

        #Invoke Antscript for Branch specific promotion
        arguments="-Dbuild.deps.dir=${BldDepsDir} -Dreleng.repo.dir=${RELENG_REPO} -Dgit.exec=${GIT_EXEC}"
        arguments="${arguments} -Dbranch.name=${branch_nm} -Drelease.version=${version} -Dbuild.type=${milestone} -Dbranch=${branch}"
        arguments="${arguments} -Dversion.qualifier=${qualifier} -Dbuild.date=${blddate} -Dgit.hash=${githash}"

        # Run Ant from ${exec_location} using ${buildfile} ${arguments}
        echo "pwd='`pwd`"
        echo "ant ${BUILDFILE} ${arguments} ${ANT_TARGET}"
        if [ -f ${BUILDFILE} ] ; then
            ant -f ${BUILDFILE} ${arguments} ${ANT_TARGET}
            if [ "$?" = "0" ]
            then
                echo "Ant promote complete."
            else
                echo "Ant Promote Failed!"
            fi
        else
            echo "'${BUILDFILE}' doesn't exist. Aborting ant run..."
        fi
    else
        # Something is not right! skipping.."
        echo "    Required locations and data failed to verify... aborting Promote...."
        ERROR=true
        if [ "${DEBUG}" = "true" ] ; then
            echo "callAnt: Required locations and data:"
            echo "   milestone = '${milestone}'"
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

#==========================
#   Validate run parameters
if [ "${BUILD}" = "" ] ; then
    usage
    echo " "
    echo "BUILD not specified! Exiting..."
    exit 1
fi
if [ "${MILESTONE}" = "" ] ; then
    usage
    echo " "
    echo "MILESTONE not specified! Exiting..."
    exit 1
fi
if [ "${BRANCH_NM}" = "" ] ; then
    usage
    echo " "
    echo "BRANCH_NM not specified! Exiting..."
    exit 1
fi
#  If anything is in ARG4 then do a dummy "DEBUG" run
#  (Do not call ant, do not modify or create files, do report variable states)
if [ -n "$ARG4" ] ; then
    DEBUG=true
    echo "Debug is on!"
fi

#==========================
#   Validate environment
echo "-= Validate Environment =- "
if [ ! -d ${JAVA_HOME} ] ; then
    echo "Expecting Java at: '${JAVA_HOME}', but is not there!"
    JAVA_HOME=/shared/common/jdk1.6.0_05
    if [ ! -d ${JAVA_HOME} ] ; then
        echo "Tried again. Expecting Java at: '${JAVA_HOME}', but is not there!"
        #exit
    fi
fi
echo "JAVA_HOME verified at: '${JAVA_HOME}'"

if [ ! -d ${ANT_HOME} ] ; then
    echo "Expecting Ant at: '${ANT_HOME}', but is not there!"
    #exit
fi
echo "ANT_HOME verified at: '${ANT_HOME}'"

if [ ! -d ${HOME_DIR} ] ; then
    echo "Need to create HOME_DIR '${HOME_DIR}'"
    if [ "${DEBUG}" = "false" ] ; then
        echo "DEBUG=$DEBUG"
        createPath ${HOME_DIR}
    else
        echo "    Debug on, No actual work being done."
    fi
fi
if [ ! -d ${LOG_DIR} ] ; then
    echo "Need to create LOG_DIR '${LOG_DIR}'"
    if [ "${DEBUG}" = "false" ] ; then
        createPath ${LOG_DIR}
    else
        echo "    Debug on, No actual work being done."
    fi
fi
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
if [ ! -d ${RELENG_REPO} ] ; then
    echo "Releng repo missing! Will set flag to create."
    #releng doest exist clone it (if git was found).
else
    echo "Releng repo found."
fi
if [ ! -d ${RUNTIME_REPO} ] ; then
    echo "EclipseLink Runtime repo missing! Will set flag to create."
    #runtime doest exist clone it (if git was found).
else
    echo "EclipseLink Runtime repo found."
fi
echo "   Validated."
echo " "

## Convert "BRANCH" to BRANCH_NM (version or trunk) and BRANCH (svn branch path)
#    BRANCH_NM is used for reporting and naming purposes
#    BRANCH    is used to quailify the actual Branch path

#==========================
#   Begin WORK
echo "Promote begin at: ${START_DATE}"

#TODO:::
#validateGitRepo

#Determine if 'release' run or regular Milestone promotion
if [ "$qualifier" = "release" ] ; then
    RELEASE=true
    # TODO: If RELEASE is set need to verify Milestone, and afer resolving BRANCH_NM to BRANCH,
    #       parse QUALIFIER from Milestone filename, and derive date and hash from qualifier
else
# TODO: Need to change to verify branch from autobuild.properties if possible, else just parse qualifier for date and hash
    # Get needed info from BUILD
    parseBuild $BUILD

    # Validate BUILD Exists
    validateBuild

    # Validate MILESTONE against convention, and verify not preexisting
    validateMilestone $MILESTONE

fi

echo "BUILD      ='${BUILD}'"
echo "  BRANCH   ='$BRANCH'"
echo "  VERSION  ='$VERSION'"
echo "QUALIFIER  ='$QUALIFIER'"
echo "  BLD_DATE ='$BLD_DATE'"
echo "  GIT_HASH ='$GIT_HASH'"
echo "MILESTONE  ='${MILESTONE}'"
echo "BRANCH_NM  ='${BRANCH_NM}'"

callAnt $MILESTONE $BRANCH $BRANCH_NM $VERSION $QUALIFIER $BLD_DATE $GIT_HASH

echo "Promote complete at: `date '+%y%m%d-%H%M'`"
echo " "
echo " "
