FROM python:3.9-slim

WORKDIR /app

# Install dependencies first (better layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire application (all services + templates + static)
COPY . .

# Default command — can be overridden per service in compose
EXPOSE 5000
CMD ["python", "app.py"]
