FROM python:3.10-alpine3.17

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip3 install -r requirements.txt


COPY . /app

EXPOSE 8081
ENTRYPOINT [ "python" ]


CMD ["app.py"]