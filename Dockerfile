# Lightweight Python image
FROM python:3.11-slim

WORKDIR /app

# Copy requirement definitions
COPY server/requirements.txt /app/server/requirements.txt

# Install dependencies
RUN pip install --no-cache-dir -r /app/server/requirements.txt

# Copy source code and frontend
COPY server /app/server
COPY frontend /app/frontend

ENV PORT=8899
EXPOSE 8899

CMD ["python", "server/server.py"]
