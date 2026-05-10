FROM python:3.12-alpine
WORKDIR /app
RUN pip install --no-cache-dir fastapi uvicorn pydantic
COPY platform/api.py ./platform/api.py
COPY envs/ ./envs/
RUN mkdir -p logs envs nginx/conf.d
EXPOSE 8000
CMD ["python", "-u", "platform/api.py"]
