FROM python:3.14-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN useradd --uid 10001 --create-home zuzu && mkdir -p /data/media && chown -R zuzu:zuzu /app /data
USER zuzu
ENV MEDIA_DIR=/data/media
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
