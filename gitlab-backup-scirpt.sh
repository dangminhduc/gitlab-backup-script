#/bin/bash
S3_BUCKET_TARGET="s3://bucket-name/folder-name/"    #where to store backed up file 
SLACK_URL="https://hooks.slack.com/services/xxxxxxxxxxxxxx" #slack channel for notification


echo $S3_BUCKET_TARGET
# Execute gitlab-backup
/opt/gitlab/bin/gitlab-rake gitlab:backup:create
if [ $? -eq 0 ]
then
        sleep 10
        #Upload the newest file to S3 folder
        echo "upload backup file to s3 bucket"
        FILE_TO_UPLOAD=`ls -Art /var/opt/gitlab/backups/*gitlab_backup.tar | tail -n 1`
        echo $FILE_TO_UPLOAD
        /usr/local/bin/aws s3 cp $FILE_TO_UPLOAD $S3_BUCKET_TARGET
        if [ $? -eq 0 ]
        then
                sleep 5
                #Delete the uploaded file
                echo "delete uploaded file:$FILE_TO_UPLOAD"
                rm -rf $FILE_TO_UPLOAD
                if [ $? -eq 0 ]
                then
                # List file for sure
                ls -l /var/opt/gitlab/backups
                else
                        echo "Deleting file is failed"
                        curl -X POST -H 'Content-type: application/json' --data '{"text":":exclamation: GitLab has successfully backed up and the file was successfully uploaded but the created file cannot be deleted\nPlease re-check the backup folder: /var/opt/gitlab/backups/."}' $SLACK_URL
                fi
        else
                echo "File upload failed!"
                curl -X POST -H 'Content-type: application/json' --data '{"text":":exclamation: GitLab has successfully backed up but file uploading was failed!\nPlease re-check aws credentials."}' $SLACK_URL
        fi
else
        echo "Backup has failed "
        curl -X POST -H 'Content-type: application/json' --data '{"text":":exclamation: AdGame backup has failed!\nPlease re-check backup settings."}' $SLACK_URL
fi
