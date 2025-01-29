#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}开始安装交易策略平台...${NC}"

# 创建项目目录
mkdir -p trading_bot
cd trading_bot

# 创建必要的子目录
mkdir -p templates strategies

# 1. 创建 requirements.txt
echo -e "${GREEN}创建 requirements.txt...${NC}"
cat > requirements.txt << EOF
flask==2.0.1
ccxt==4.4.52
pandas==1.3.3
numpy==1.21.2
python-dotenv==0.19.0
gunicorn==20.1.0
EOF

# 2. 创建 app.py
echo -e "${GREEN}创建 app.py...${NC}"
cat > app.py << EOF
from flask import Flask, jsonify, request
import ccxt
import time

app = Flask(__name__)

class ExchangeLatencyMonitor:
    def __init__(self):
        self.exchanges = {
            'binance': {
                'spot': ccxt.binance({
                    'enableRateLimit': True,
                    'options': {'defaultType': 'spot'}
                }),
                'future': ccxt.binance({
                    'enableRateLimit': True,
                    'options': {'defaultType': 'future'}
                })
            }
        }
        self.latency_history = []
        
    def test_latency(self):
        results = {}
        for exchange_name, markets in self.exchanges.items():
            results[exchange_name] = {}
            for market_type, exchange in markets.items():
                try:
                    start_time = time.time()
                    exchange.fetch_time()
                    ping = (time.time() - start_time) * 1000
                    
                    start_time = time.time()
                    exchange.fetch_ticker('BTC/USDT')
                    ticker_latency = (time.time() - start_time) * 1000
                    
                    results[exchange_name][market_type] = {
                        'ping': round(ping, 2),
                        'ticker_latency': round(ticker_latency, 2),
                        'status': 'ok',
                        'timestamp': time.time()
                    }
                except Exception as e:
                    results[exchange_name][market_type] = {
                        'status': 'error',
                        'error': str(e),
                        'timestamp': time.time()
                    }
                    
        self.latency_history.append({
            'timestamp': time.time(),
            'data': results
        })
        if len(self.latency_history) > 100:
            self.latency_history.pop(0)
            
        return results

latency_monitor = ExchangeLatencyMonitor()

@app.route('/')
def index():
    return app.send_static_file('index.html')

@app.route('/api/latency', methods=['GET'])
def get_latency():
    return jsonify(latency_monitor.test_latency())

@app.route('/api/latency/history', methods=['GET'])
def get_latency_history():
    return jsonify(latency_monitor.latency_history)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# 3. 创建 static/index.html
mkdir -p static
echo -e "${GREEN}创建 static/index.html...${NC}"
cat > static/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Exchange Latency Monitor</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/jquery@3.6.0/dist/jquery.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        .latency-good { color: #28a745; }
        .latency-warning { color: #ffc107; }
        .latency-bad { color: #dc3545; }
        #latencyChart { height: 300px; }
    </style>
</head>
<body>
    <div class="container mt-4">
        <h2>Exchange Latency Monitor</h2>
        <div class="row">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        Current Latency
                        <button class="btn btn-sm btn-primary float-end" onclick="refreshLatency()">
                            Refresh
                        </button>
                    </div>
                    <div class="card-body">
                        <div id="latency-panel">
                            <div class="mb-3">
                                <h6>Binance Spot</h6>
                                <div class="d-flex justify-content-between">
                                    <small>Ping:</small>
                                    <span id="binance-spot-ping">-</span>
                                </div>
                                <div class="d-flex justify-content-between">
                                    <small>Ticker:</small>
                                    <span id="binance-spot-ticker">-</span>
                                </div>
                            </div>
                            <div class="mb-3">
                                <h6>Binance Future</h6>
                                <div class="d-flex justify-content-between">
                                    <small>Ping:</small>
                                    <span id="binance-future-ping">-</span>
                                </div>
                                <div class="d-flex justify-content-between">
                                    <small>Ticker:</small>
                                    <span id="binance-future-ticker">-</span>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">Latency History</div>
                    <div class="card-body">
                        <canvas id="latencyChart"></canvas>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let latencyChart;

        function initLatencyChart() {
            const ctx = document.getElementById('latencyChart').getContext('2d');
            latencyChart = new Chart(ctx, {
                type: 'line',
                data: {
                    labels: [],
                    datasets: [{
                        label: 'Spot Ping',
                        data: [],
                        borderColor: 'rgb(75, 192, 192)',
                        tension: 0.1
                    }, {
                        label: 'Future Ping',
                        data: [],
                        borderColor: 'rgb(255, 99, 132)',
                        tension: 0.1
                    }]
                },
                options: {
                    responsive: true,
                    scales: {
                        y: {
                            beginAtZero: true
                        }
                    }
                }
            });
        }

        function updateLatency() {
            $.get('/api/latency', function(data) {
                if (data.binance) {
                    if (data.binance.spot) {
                        $('#binance-spot-ping').text(\`\${data.binance.spot.ping}ms\`);
                        $('#binance-spot-ticker').text(\`\${data.binance.spot.ticker_latency}ms\`);
                    }
                    if (data.binance.future) {
                        $('#binance-future-ping').text(\`\${data.binance.future.ping}ms\`);
                        $('#binance-future-ticker').text(\`\${data.binance.future.ticker_latency}ms\`);
                    }
                }
                updateLatencyChart();
            });
        }

        function updateLatencyChart() {
            $.get('/api/latency/history', function(history) {
                const labels = history.map(item => {
                    return new Date(item.timestamp * 1000).toLocaleTimeString();
                });
                
                const spotData = history.map(item => {
                    return item.data.binance?.spot?.ping || null;
                });
                
                const futureData = history.map(item => {
                    return item.data.binance?.future?.ping || null;
                });
                
                latencyChart.data.labels = labels;
                latencyChart.data.datasets[0].data = spotData;
                latencyChart.data.datasets[1].data = futureData;
                latencyChart.update();
            });
        }

        function refreshLatency() {
            updateLatency();
        }

        $(document).ready(function() {
            initLatencyChart();
            updateLatency();
            setInterval(updateLatency, 5000);
        });
    </script>
</body>
</html>
EOF

# 4. 创建 Dockerfile
echo -e "${GREEN}创建 Dockerfile...${NC}"
cat > Dockerfile << EOF
FROM python:3.9-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
COPY . .

RUN pip install --no-cache-dir -r requirements.txt
RUN mkdir -p strategies

ENV FLASK_APP=app.py
ENV FLASK_ENV=production

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]
EOF

# 5. 创建 docker-compose.yml
echo -e "${GREEN}创建 docker-compose.yml...${NC}"
cat > docker-compose.yml << EOF
version: '3'

services:
  web:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - ./strategies:/app/strategies
    environment:
      - FLASK_ENV=production
    restart: always
EOF

# 6. 检查并安装 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}安装 Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi

# 7. 检查并安装 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}安装 Docker Compose...${NC}"
    sudo apt-get install -y docker-compose
fi

# 8. 构建和启动服务
echo -e "${GREEN}构建和启动服务...${NC}"
docker-compose up -d --build

echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}访问 http://你的服务器IP:5000 来查看延迟监控${NC}"
