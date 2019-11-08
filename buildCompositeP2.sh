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
            echo "USAGE: ./buildCompositeP2.sh site_dir site_name"
            echo "   where:"
            echo "      site_dir  = the location of the compositeRepository with"
            echo "                  child repositories already present under it"
            echo "      site_name = string designating the compositeRepository name"
            exit
fi

# safe temp directory
tmp=${TMPDIR-/tmp}
tmp=$tmp/somedir.$RANDOM.$RANDOM.$RANDOM.$$
(umask 077 && mkdir $tmp) || {
  echo "Could not create temporary directory! Exiting." 1>&2
  exit 1
}

#------- Subroutines -------#
unset genContent
genContent() {
    # Generate the nightly build table
    echo "<?xml version='1.0' encoding='UTF-8'?>" > $tmp/content.xml
    echo "<?compositeMetadataRepository version='1.0.0'?>" >> $tmp/content.xml
    echo "<repository name='&quot;${SITE_NAME}&quot;' type='org.eclipse.equinox.internal.p2.metadata.repository.CompositeMetadataRepository' version='1.0.0'>" >> $tmp/content.xml
    echo "  <properties size='1'>" >> $tmp/content.xml
    echo "    <property name='p2.timestamp' value='1267023743270'/>" >> $tmp/content.xml
    echo "  </properties>" >> $tmp/content.xml
    echo "  <children size='${child_count}'>" >> $tmp/content.xml
    echo "    <child location='categories'/>" >> $tmp/content.xml
    cat $tmp/children.xml >> $tmp/content.xml
    echo "  </children>" >> $tmp/content.xml
    echo "</repository>" >> $tmp/content.xml
}

unset genArtifact
genArtifact() {
    artifact_count=`expr $child_count - 1`
    # Generate the nightly build table
    echo "<?xml version='1.0' encoding='UTF-8'?>" > $tmp/artifact.xml
    echo "<?compositeArtifactRepository version='1.0.0'?>" >> $tmp/artifact.xml
    echo "<repository name='&quot;${SITE_NAME}&quot;' type='org.eclipse.equinox.internal.p2.artifact.repository.CompositeArtifactRepository' version='1.0.0'>" >> $tmp/artifact.xml
    echo "  <properties size='1'>" >> $tmp/artifact.xml
    echo "    <property name='p2.timestamp' value='1267023743270'/>" >> $tmp/artifact.xml
    echo "  </properties>" >> $tmp/artifact.xml
    echo "  <children size='${artifact_count}'>" >> $tmp/artifact.xml
    cat $tmp/children.xml >> $tmp/artifact.xml
    echo "  </children>" >> $tmp/artifact.xml
    echo "</repository>" >> $tmp/artifact.xml
}

unset genIndexPage
genIndexPage() {
    # Generate index.html page
    echo '<html><head><title>EclipseLink Update Site</title><base href="http://download.eclipse.org/" />' > $tmp/indexTmp.html
    echo '<link rel="stylesheet" type="text/css" href="/eclipse.org-common/themes/Nova/css/reset.css"/><link rel="stylesheet" type="text/css" href="/eclipse.org-common/themes/Nova/css/layout.css" media="screen" /><link rel="stylesheet" type="text/css" href="/eclipse.org-common/themes/Nova/css/header.css" media="screen" /><link rel="stylesheet" type="text/css" href="/eclipse.org-common/themes/Nova/css/footer.css" media="screen" /><link rel="stylesheet" type="text/css" href="/eclipse.org-common/themes/Nova/css/visual.css" media="screen" /></head>' >> $tmp/indexTmp.html
    echo '<body><div id="novaWrapper"><div id="clearHeader"><div id="logo">' >> $tmp/indexTmp.html
    echo '<img src="/eclipse.org-common/themes/Nova/images/eclipse.png" alt="Eclipse.org"/></div></div><div id="header"><div id="menu"><ul>' >> $tmp/indexTmp.html
    echo '<li><a href="//eclipse.org">Home</a></li><li><a href="//eclipse.org/downloads">Downloads</a></li><li><a href="//eclipse.org/users">Users</a></li><li><a href="//eclipse.org/membership">Members</a></li><li><a href="//eclipse.org/committers">Committers</a></li><li><a href="//eclipse.org/resources">Resources</a></li><li><a href="//eclipse.org/projects">Projects</a></li><li><a href="//eclipse.org/org">About Us</a></li>' >> $tmp/indexTmp.html
    echo '</ul></div><div id="search"><form action="http://www.google.com/cse" id="searchbox_017941334893793413703:sqfrdtd112s"><input type="hidden" name="cx" value="017941334893793413703:sqfrdtd112s" /><input id="searchBox" type="text" name="q" size="25" /><input id="searchButton" type="submit" name="sa" value="Search" /></form><script type="text/javascript" src="http://www.google.com/coop/cse/brand?form=searchbox_017941334893793413703%3Asqfrdtd112s&lang=en"></script></div></div>' >> $tmp/indexTmp.html
    echo '<div id="novaContent"><div id="fullcolumn"><div id="midcolumn"><h1>EclipseLink Update Site</h1>' >> $tmp/indexTmp.html
    echo '    <p>This landing page exists to allow visibility to the P2 update site''s URL, and zipped P2 archives. </font> </p>' >> $tmp/indexTmp.html
    echo '    <h4>The URL is intended for use with:</h4>' >> $tmp/indexTmp.html
    echo '    	<ul><li>Eclipse''s "Target Platform" creation <b>(Window|Preferences..|Plug-in Development|Target Platform)</b> and </li>' >> $tmp/indexTmp.html
    echo '    		<li> Update  tools <b>(Help|Update Software)</b>.</li></ul>' >> $tmp/indexTmp.html
    echo '    		    All downloads are provided under the <a href="http://www.eclipse.org/eclipselink/project-info/license.html">' >> $tmp/indexTmp.html
    echo '                <b>Eclipse Foundation Software User Agreement</b></a>.<p>' >> $tmp/indexTmp.html
    echo '</p>' >> $tmp/indexTmp.html
    echo '<div id="rightcolumn"><div class="sideitem"><h6>Downloadable Zipped P2 Repositories</h6>' >> $tmp/indexTmp.html
    echo '<ul>' >> $tmp/indexTmp.html
    cat $tmp/childrenHtml.html >> $tmp/indexTmp.html
    echo '    </ul>' >> $tmp/indexTmp.html
    echo '</div>' >> $tmp/indexTmp.html
    echo '<div id="rightcolumn"><div class="sideitem"><h6>Useful links</h6>' >> $tmp/indexTmp.html
    echo '    <ul><li><a href="http://www.eclipse.org/eclipselink/releases/">EclipseLink Releases</a></li></ul>' >> $tmp/indexTmp.html
    echo '</div>' >> $tmp/indexTmp.html
    echo '</div></div>' >> $tmp/indexTmp.html
    echo '<br style="clear:both;height:1em;"/>&nbsp;</div><div id="clearFooter"></div><div id="footer"><ul id="footernav"><li><a href="//eclipse.org/">Home</a></li><li><a href="//eclipse.org/legal/privacy.php">Privacy Policy</a></li><li><a href="//eclipse.org/legal/termsofuse.php">Terms of Use</a></li><li><a href="//eclipse.org/legal/copyright.php">Copyright Agent</a></li><li><a href="//eclipse.org/legal">Legal</a></li><li><a href="//eclipse.org/org/foundation/contact.php">Contact Us</a></li></ul><span id="copyright">Copyright &copy; 2013 The Eclipse Foundation. All Rights Reserved.</span></div></div></body></html>' >> $tmp/indexTmp.html
}

unset genChildren
genChildren() {
    for child in `ls -dr [0-9]* | grep -v zip` ; do
        child_count=`expr $child_count + 1`
        echo "    <child location='${child}'/>" >> $tmp/children.xml
    done
}

unset genHtmlChildren
genHtmlChildren() {
    for child in `ls -dr [0-9]* | grep zip` ; do
        echo "        <li><a href='http://www.eclipse.org/downloads/download.php?file=/rt/eclipselink/updates/${child}'/>${child}</a></li>" >> $tmp/childrenHtml.html
    done
}

#------- MAIN -------#
cd ${SITE_DIR}
echo "generating Composite Repository..."
echo "    At:     '${SITE_DIR}'"
echo "    Called: '${SITE_NAME}'"

#  child_count is 1 because there will always be a child
#  for the categories (which wo't be counted)
child_count=1
genChildren
genContent
genArtifact

if [ "$1" = "release" ]
then
    genHtmlChildren
    genIndexPage
    mv -f $tmp/indexTmp.html  ${SITE_DIR}/index.html
fi

# Copy the completed file to the server, and cleanup
mv -f $tmp/content.xml  ${SITE_DIR}/compositeContent.xml
mv -f $tmp/artifact.xml ${SITE_DIR}/compositeArtifacts.xml
rm -rf $tmp
