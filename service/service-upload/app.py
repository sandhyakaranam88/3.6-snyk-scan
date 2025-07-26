from flask import Flask, request
import boto3, os

app = Flask(__name__)
s3 = boto3.client('s3')
BUCKET = os.environ['BUCKET']

@app.route('/upload', methods=['POST'])
def upload():
    file = request.files['file']
    s3.put_object(Bucket=BUCKET, Key=file.filename, Body=file)
    return f"Uploaded {file.filename}", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
