from flask import Flask, request
import boto3, os

app = Flask(__name__)
sqs = boto3.client('sqs')
QUEUE_URL = os.environ['QUEUE_URL']

@app.route('/send', methods=['POST'])
def send():
    msg = request.form['message']
    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=msg)
    return f"Sent '{msg}'", 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
