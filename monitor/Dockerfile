FROM python:3.12-alpine
RUN pip install --no-cache-dir requests
WORKDIR /app
COPY monitor/health_poller.py ./monitor/health_poller.py
RUN mkdir -p logs envs
CMD ["python", "-u", "monitor/health_poller.py"]
