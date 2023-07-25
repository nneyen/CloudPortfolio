from flask import (Flask, render_template, request, redirect, url_for)

app = Flask (__name__)

@app.route('/')
def home():
    return 'Welcome to My Flask App, proceed to the login page (/login)'
@app.route('/dashboard/<name>')
def dashboard(name):
    return 'Welcome %s' % name
@app.route('/login', methods = ['POST', 'GET'])
def login():
    if request.method == 'POST':
        user = request.form['name']
        return redirect(url_for('dashboard', name = user))
    else:
        user = request.args.get('name')
        return render_template('login.html')

if __name__ =='__main__':
    app.run(threaded=True, host='0.0.0.0', port=8081)