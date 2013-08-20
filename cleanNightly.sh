# !/bin/sh
#set -x

# Cleanup old builds from publish area, and repos

version=$1
BaseDownloadNFSDir="/home/data/httpd/download.eclipse.org/rt/eclipselink"
buildir=/shared/rt/eclipselink


unset usage
usage() {
    echo " "
    echo "Usage: `basename $0` [version]"
    echo "  version  Name of version for which old builds will be cleaned."
}

unset validateVersion
validateVersion() {
    runVersion=$1

    cd ${BaseDownloadNFSDir}/nightly
    for validVersion in `ls -dr [0-9]*` ; do
        if [ "${validVersion}" = "${runVersion}" ] ; then
            echo "Version found. ${runVersion} valid..."
            valid=true
        fi
    done
    if [ ! "$valid" = "true" ] ; then
       echo "Version not present in nightly. '${runVersion}' isn't a valid or active version..."
       error=true
    fi
}

unset cleanNightlyDir
cleanNightlyDir() {
    DownloadDir=${BaseDownloadNFSDir}/nightly/${workingVersion}
    #      leave only the last 10 build dirs for the version on the download server
    if [ -d ${DownloadDir} ] ; then
        index=0
        removed=0
        cd ${DownloadDir}
        for contentdir in `ls -dr [0-9]*` ; do
            index=`expr $index + 1`
            if [ $index -gt $num_builds ] ; then
                echo "Removing ${contentdir}..."
                rm -r $contentdir
                removed=`expr $removed + 1`
            fi
        done
        echo "Removed $removed directories from ${BaseDownloadNFSDir}/nightly/${workingVersion}."
    else
        error=true
    fi
}

unset cleanP2NightlySite
cleanP2NightlySite() {
    #   leave only the last "num_p2_builds" builds for the version in the nightly P2 repos
    index=0
    removed=0
    cd ${BaseDownloadNFSDir}/nightly-updates
    for contentdir in `ls -dr ${workingVersion}*` ; do
        index=`expr $index + 1`
        if [ $index -gt $num_p2_builds ] ; then
            echo "Removing ${contentdir}..."
            rm -r $contentdir
            removed=`expr $removed + 1`
        fi
    done
    echo "Removed $removed direcories from ${BaseDownloadNFSDir}/nightly-updates."
}

unset cleanMavenNightlySite
cleanMavenNightlySite() {
    if [ "true" = "true" ] ; then
        echo "TODO: Need to verify the "correct" way to clean the maven repo of old SNAPSHOTs"
        echo "      In the meantime nothing in the maven repo is cleaned!!"
    else
        #      leave only last 5 days worth of files in the maven repository
        cd ${BaseDownloadNFSDir}/maven.repo/org/eclipse/persistence
        for mvncomp in `ls -d *eclipse*` ; do
            index=0
            removed=0
            cd ${BaseDownloadNFSDir}/maven.repo/org/eclipse/persistence/${mvncomp}/${workingVersion}-SNAPSHOT
            for mvnfile in `ls -r ${mvncomp}*.*` ; do
                index=`expr $index + 1`
                if [ $index -gt $num_maven_files ] ; then
                   echo "Removing ${mvnfile}..."
                   rm $mvnfile
                   removed=`expr $removed + 1`
                fi
            done
            echo "Removed $removed files from ${BaseDownloadNFSDir}/maven.repo/org/eclipse/persistence/${mvncomp}/${workingVersion}-SNAPSHOT."
        done
    fi
}

##############################################
#
# MAIN
#
if [ ! \( \( -z "$version" \) -o \( "$version" = "" \) \) ] ; then
   validateVersion ${version}
   if [ "$error" = "true" ] ; then
       echo "$version not found!"
       exit 1
   fi
else
   cd ${BaseDownloadNFSDir}/nightly
   version=`ls -dr [0-9]*`
fi

if [ "input" = "release" ]
then
   # When releasing clear all nightly builds
   num_builds=0
   num_p2_builds=0
   num_maven_builds=0
else
   num_builds=10
   num_p2_builds=5
   # Maven: 5 builds * 9 files/build = 45
   num_maven_files=45
fi

for workingVersion in ${version} ; do
   cd ${buildir}
   echo "Purging old builds of '${workingVersion}'..."

   ### Download Site ###
   cleanNightlyDir
   if [ "$error" = "true" ] ; then
      echo "No '${BaseDownloadNFSDir}/nightly/${workingVersion}' dir found!"
      echo "    Assuming invalid version number, and aborting clean."
      exit
   fi
   
   ### P2 Site ###
   cleanP2NightlySite
   
   ### Maven Site ###
   cleanMavenNightlySite   
done
cd ${buildir}
