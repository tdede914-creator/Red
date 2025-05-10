FROM ubuntu:20.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
WORKDIR /app
COPY . /app

# Install project dependencies
RUN npm install

# Expose port for testing (misalnya port 8080)
EXPOSE 8080

# Command to run server
CMD ["npm", "start"]
