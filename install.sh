#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}开始安装交易策略平台...${NC}"

# 创建项目目录
mkdir -p trading-platform
cd trading-platform

# 创建必要的子目录
mkdir -p templates strategies

# 1. 创建 requirements.txt
echo -e "${GREEN}创建 requirements.txt...${NC}"
cat > requirements.txt << EOF
flask==2.0.1
ccxt==3.0.0
pandas==1.3.3
numpy==1.21.2
python-dotenv==0.19.0
gunicorn==20.1.0
EOF

# 2. 创建 Dockerfile
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

# 3. 创建 docker-compose.yml
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
    
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - web
EOF

# 4. 创建 nginx.conf
echo -e "${GREEN}创建 nginx.conf...${NC}"
cat > nginx.conf << EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://web:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# 5. 创建 app.py
echo -e "${GREEN}创建 app.py...${NC}"
cat > app.py << 'EOF'
from flask import Flask, render_template, jsonify, request
import json
import os
from datetime import datetime
import ccxt
import threading

app = Flask(__name__)

class StrategyManager:
    def __init__(self):
        self.strategies = {}
        self.running_tasks = {}
        self.logs = {}
        
    def add_strategy(self, name, code):
        self.strategies[name] = {
            'code': code,
            'created_at': datetime.now(),
            'status': 'stopped'
        }
        
    def run_strategy(self, name):
        if name not in self.strategies:
            return False
            
        if name in self.running_tasks:
            return False
            
        strategy_globals = {
            'ccxt': ccxt,
            'print': lambda x: self.log(name, x)
        }
        
        try:
            exec(self.strategies[name]['code'], strategy_globals)
        except Exception as e:
            self.log(name, f"Strategy compilation error: {str(e)}")
            return False
            
        def run_wrapper():
            try:
                strategy_globals['main']()
            except Exception as e:
                self.log(name, f"Strategy runtime error: {str(e)}")
                
        thread = threading.Thread(target=run_wrapper)
        thread.start()
        self.running_tasks[name] = thread
        self.strategies[name]['status'] = 'running'
        return True
        
    def stop_strategy(self, name):
        if name not in self.running_tasks:
            return False
            
        self.strategies[name]['status'] = 'stopped'
        del self.running_tasks[name]
        return True
        
    def log(self, strategy_name, message):
        if strategy_name not in self.logs:
            self.logs[strategy_name] = []
        self.logs[strategy_name].append({
            'time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'message': str(message)
        })

strategy_manager = StrategyManager()

@app.route('/')
def index():
    return render_template('index.html', strategies=strategy_manager.strategies)

@app.route('/api/strategies', methods=['GET'])
def list_strategies():
    return jsonify(strategy_manager.strategies)

@app.route('/api/strategies', methods=['POST'])
def create_strategy():
    data = request.json
    strategy_manager.add_strategy(data['name'], data['code'])
    return jsonify({'status': 'success'})

@app.route('/api/strategies/<name>/run', methods=['POST'])
def run_strategy(name):
    success = strategy_manager.run_strategy(name)
    return jsonify({'status': 'success' if success else 'error'})

@app.route('/api/strategies/<name>/stop', methods=['POST'])
def stop_strategy(name):
    success = strategy_manager.stop_strategy(name)
    return jsonify({'status': 'success' if success else 'error'})

@app.route('/api/strategies/<name>/logs', methods=['GET'])
def get_logs(name):
    return jsonify(strategy_manager.logs.get(name, []))

if __name__ == '__main__':
    app.run(debug=True)
EOF

# 6. 创建 templates/index.html
echo -e "${GREEN}创建 index.html...${NC}"
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Strategy Manager</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/theme/monokai.min.css" rel="stylesheet">
    <style>
        .CodeMirror { height: 500px; border: 1px solid #ddd; }
        .log-window { height: 300px; overflow-y: auto; background: #2d2d2d; color: #fff; padding: 10px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container-fluid">
        <div class="row">
            <div class="col-md-3">
                <div class="card mt-3">
                    <div class="card-header">
                        Strategies
                        <button class="btn btn-sm btn-primary float-end" onclick="newStrategy()">New</button>
                    </div>
                    <div class="card-body">
                        <div id="strategy-list" class="list-group"></div>
                    </div>
                </div>
            </div>
            <div class="col-md-9">
                <div class="card mt-3">
                    <div class="card-header">
                        <span id="current-strategy">Strategy Editor</span>
                        <div class="float-end">
                            <button class="btn btn-sm btn-success" onclick="runStrategy()">Run</button>
                            <button class="btn btn-sm btn-danger" onclick="stopStrategy()">Stop</button>
                            <button class="btn btn-sm btn-primary" onclick="saveStrategy()">Save</button>
                        </div>
                    </div>
                    <div class="card-body">
                        <textarea id="editor"></textarea>
                    </div>
                </div>
                <div class="card mt-3">
                    <div class="card-header">
                        Logs
                        <button class="btn btn-sm btn-secondary float-end" onclick="clearLogs()">Clear</button>
                    </div>
                    <div class="card-body">
                        <div id="log-window" class="log-window"></div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/codemirror.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.2/mode/python/python.min.js"></script>
    
    <script>
        let editor;
        let currentStrategy = null;
        
        $(document).ready(function() {
            editor = CodeMirror.fromTextArea(document.getElementById("editor"), {
                mode: "python",
                theme: "monokai",
                lineNumbers: true,
                indentUnit: 4
            });
            
            loadStrategies();
            setInterval(updateLogs, 1000);
        });
        
        function loadStrategies() {
            $.get('/api/strategies', function(strategies) {
                let html = '';
                for (let name in strategies) {
                    html += `
                        <a href="#" class="list-group-item list-group-item-action" 
                           onclick="loadStrategy('${name}')">
                            ${name}
                            <span class="badge bg-${strategies[name].status === 'running' ? 'success' : 'secondary'} float-end">
                                ${strategies[name].status}
                            </span>
                        </a>
                    `;
                }
                $('#strategy-list').html(html);
            });
        }
        
        function loadStrategy(name) {
            currentStrategy = name;
            $('#current-strategy').text(name);
            editor.setValue(strategies[name].code);
        }
        
        function newStrategy() {
            let name = prompt("Enter strategy name:");
            if (name) {
                currentStrategy = name;
                $('#current-strategy').text(name);
                editor.setValue('# New Strategy\n\ndef main():\n    pass');
            }
        }
        
        function saveStrategy() {
            if (!currentStrategy) return;
            
            $.ajax({
                url: '/api/strategies',
                method: 'POST',
                contentType: 'application/json',
                data: JSON.stringify({
                    name: currentStrategy,
                    code: editor.getValue()
                }),
                success: function() {
                    loadStrategies();
                }
            });
        }
        
        function runStrategy() {
            if (!currentStrategy) return;
            
            $.post(`/api/strategies/${currentStrategy}/run`, function() {
                loadStrategies();
            });
        }
        
        function stopStrategy() {
            if (!currentStrategy) return;
            
            $.post(`/api/strategies/${currentStrategy}/stop`, function() {
                loadStrategies();
            });
        }
        
        function updateLogs() {
            if (!currentStrategy) return;
            
            $.get(`/api/strategies/${currentStrategy}/logs`, function(logs) {
                let html = '';
                logs.forEach(log => {
                    html += `<div>[${log.time}] ${log.message}</div>`;
                });
                $('#log-window').html(html);
                $('#log-window').scrollTop($('#log-window')[0].scrollHeight);
            });
        }
        
        function clearLogs() {
            $('#log-window').html('');
        }
    </script>
</body>
</html>
EOF

# 7. 检查并安装 Docker
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}安装 Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi

# 8. 检查并安装 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${GREEN}安装 Docker Compose...${NC}"
    sudo apt-get install -y docker-compose
fi

# 9. 构建和启动服务
echo -e "${GREEN}构建和启动服务...${NC}"
docker-compose up -d --build

echo -e "${GREEN}安装完成！${NC}"
echo -e "${GREEN}访问 http://localhost 或者 http://服务器IP 来使用平台${NC}"

# 创建一个默认策略示例
mkdir -p strategies
cat > strategies/example.py << EOF
def main():
    print("这是一个示例策略")
    # 在这里编写你的交易逻辑
EOF
