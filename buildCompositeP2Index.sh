# !/bin/sh
#set -x

RELEASE_SITE_DIR=/home/data/httpd/download.eclipse.org/rt/eclipselink/updates
RELEASE_SITE_NAME="EclipseLink Release Repository"
MILESTONE_SITE_DIR=/home/data/httpd/download.eclipse.org/rt/eclipselink/milestone-updates
MILESTONE_SITE_NAME="EclipseLink Milestone Repository"
NIGHTLY_SITE_DIR=/home/data/httpd/download.eclipse.org/rt/eclipselink/nightly-updates
NIGHTLY_SITE_NAME="EclipseLink Nightly Build Repository"
CMD_ERROR=false
SITE_DIR=$1
SITE_NAME=$2
if [ "${SITE_DIR}" = "release" ]
then
    SITE_DIR=${RELEASE_SITE_DIR}
    SITE_NAME=${RELEASE_SITE_NAME}
fi
if [ "${SITE_DIR}" = "milestone" ]
then
    SITE_DIR=${MILESTONE_SITE_DIR}
    SITE_NAME=${MILESTONE_SITE_NAME}
fi
if [ "${SITE_DIR}" = "nightly" ]
then
    SITE_DIR=${NIGHTLY_SITE_DIR}
    SITE_NAME=${NIGHTLY_SITE_NAME}
fi

if [ "${SITE_DIR}" = "" ]
then
    echo "ERROR: Site location must be specified!"
    CMD_ERROR=true
fi
if [ ! -d ${SITE_DIR} ]
then
    echo "ERROR: Need to generate the children repositories before generating the composite!"
    CMD_ERROR=true
fi
if [ "${SITE_NAME}" = "" ]
then
    echo "ERROR: Site name must be specified!"
    CMD_ERROR=true
fi
if [ "${CMD_ERROR}" = "true" ]
then
            echo "USAGE: ./buildCompositeP2Index.sh site_dir site_name"
            echo "   where:"
            echo "      site_dir  = the location of the compositeRepository with"
            echo "                  child repositories already present under it"
            echo "      site_name = string designating the compositeRepository name"
            exit
fi

#This is temporary solution
sed -i  -e 's+<li><a href="http://www.eclipse.org/downloads/download.php?file=/rt/eclipselink/updates/2.7.4.v20190115-ad5b7c6b2a.zip">2.7.4.v20190115-ad5b7c6b2a.zip</a></li>+<li><a href="http://www.eclipse.org/downloads/download.php?file=/rt/eclipselink/updates/2.7.5.v20191016-ea124dd158.zip">2.7.5.v20191016-ea124dd158.zip</a></li>\n<li><a href="http://www.eclipse.org/downloads/download.php?file=/rt/eclipselink/updates/2.7.4.v20190115-ad5b7c6b2a.zip">2.7.4.v20190115-ad5b7c6b2a.zip</a></li>+g' ${SITE_DIR}/index.html