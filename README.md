# GitLab バックアップとリストアー手順

## I. バックアップ方法

GitLabサーバーにクローンを実行して、毎日の夜中3時にバックアップを取って、S3にあげます。
****※クローンを設定するときに、必ずクローン実行時間とrsyslogの時間を確認してください。
ずれる場合はcronとrsyslogを再起動が必要です。****
**クローン：**

```
#/etc/cron.d/gitlab-backup
0 3 * * * root /opt/gitlab-backup.sh 3 > /dev/null 2>&1
```

バックアップスクリプト

```
#/bin/bash
#S3_BUCKET_TARGET="s3://gitlabdata-backup/NetMile/"    #NetMile Backup Folder
S3_BUCKET_TARGET="s3://gitlabdata-backup/AdGame/"    #Adgame Backup Folder
#SLACK_URL="https://hooks.slack.com/services/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" #datadog_test channel
SLACK_URL="https://hooks.slack.com/services/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" #cloudwatch channel


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
                # List file for sure
                ls -l /var/opt/gitlab/backups
        else
                echo "File upload failed!"
                curl -X POST -H 'Content-type: application/json' --data '{"text":":exclamation: AdGame GitLab has successfully backed up but file uploading was failed!\nPlease re-check aws credentials."}' $SLACK_URL
        fi
else
        echo "Backup has failed "
        curl -X POST -H 'Content-type: application/json' --data '{"text":":exclamation: AdGame GitLab backup has failed!\nPlease re-check backup settings."}' $SLACK_URL
fi
```

AWSのCLIを利用するため、設定が必要です。
AWSの上でBackup用のユーザーを利用する。→「gitlab-backup」

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1434613487001",
            "Effect": "Allow",
            "Action": [
                "s3:ListAllMyBuckets"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Sid": "Stmt1434613487000",
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::gitlabdata-backup",
                "arn:aws:s3:::gitlabdata-backup/*"
            ]
        }
    ]
}
```

**サーバー以内のAWSCLIコンフィグ：**

```
[root@gitlab ~]# aws configure
AWS Access Key ID:
AWS Secret Access Key:
Default region name:
Default output format[None]:
```

Backupファイルを戻せる為、「gitlab-secrets.json」を保存する

```
#/etc/gitlab/gitlab-secrets.json
```

## **II. リストア方法：**

新しいインスタンスを作成する（Ubuntuを利用する）
適当なバージョンをインストールする

```
curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash
sudo apt-get install gitlab-ce=9.x.x-ce.0
sudo gitlab-ctl reconfigure
```

バックアップファイルを取得する

```
aws s3 cp s3://gitlabdata-backup/AdGame/xxxxxxx_xxxx_xx_xx_gitlab_backup.tar ./
sudo mkdir /var/opt/gitlab/backups
sudo mv xxxxxxxx_xxxx_xx_xx_gitlab_backup.tar /var/opt/gitlab/backups/
```

GitLabサービスを一部停止する(unicorn,sidekiq)。それから確認する

```
gitlab-ctl stop unicorn
gitlab-ctl stop sidekiq
gitlab-ctl status
```

リストアを行う

```
gitlab-rake gitlab:backup:restore BACKUP=xxxxxx_xxxx_xx_xx
```

GitLabのコンフィグファイルを上書きする。

```
aws s3 cp s3://gitlabdata-backup/gitlab-config/AdGame-gitlab.rb ./
mv AdGame-gitlab.rb /etc/gitlab/gitlab.rb
aws s3 cp s3://gitlabdata-backup/SecretJson/AdGame-gitlab-secrets.json ./
mv AdGame-gitlab-secrets.json /etc/gitlab/gitlab-secrets.json
```

GitLabサービスを再開する

```
gitlab-ctl start unicorn
gitlab-ctl start sidekiq
gitlab-ctl status
```

1分ぐらい待って、gitlab.netmile.co.jpにアクセスしてみる。
GitLabが動かない場合は、サービスを再起動する。

```
gitlab-ctl restart
```

Gitlabページアクセス、各操作(push,pull,clone)を確認する。

**※GitLabサーバーのインスタンスが変更になった場合は、ハードが変更になりましたので、
クライアント側上のknown_hostsファイルの旧サーバーのSHA署名の行をコメントアウトしてから、Gitの利用を再開してください。****ファイルパス： **C:\Users\<ユーザー名>\.ssh\known_hosts****
