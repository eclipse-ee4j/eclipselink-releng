#!/bin/bash

PRESIGNED_ZIP=$1
SIGNED_OUTPUT=$3

rm -rf presign_jars signed_jars $SIGNED_OUTPUT

#extracting presigned zip
unzip -q $PRESIGNED_ZIP -d presign_jars
find presign_jars -type d |sed 's/presign_jars/signed_jars/g' |xargs mkdir -p

#signing the jars
for j in `find presign_jars -type f -name "*.jar"`
do
    echo "signing $j ..."
    signed_jar=`echo $j |sed 's/presign_jars/signed_jars/g'`
    curl -s -o ${signed_jar} -F file=@${j} http://build.eclipse.org:31338/sign
done

mkdir -p $SIGNED_OUTPUT
cd signed_jars
zip -q -r ../${SIGNED_OUTPUT}/${PRESIGNED_ZIP} *
