# app.py
from flask import Flask, render_template, request, jsonify
import json
import os
from trader import BinanceFuturesTrader
from threading import Thread

app = Flask(__name__)

# 全局变量存储trader实例
global_trader = None
trader_thread = None

def load_config():
    """加载配置"""
    if os.path.exists('config.json'):
        with open('config.json', 'r') as f:
            return json.load(f)
    return {
        "api_key": "",
        "api_secret": "",
        "symbol": "BTC/USDT",
        "leverage": 10,
        "test_net": True,
        "trading_params": {
            "fast_length": 12,
            "slow_length": 26,
            "rsi_length": 14,
            "rsi_threshold": 20
        }
    }

def save_config(config):
    """保存配置"""
    with open('config.json', 'w') as f:
        json.dump(config, f, indent=4)

@app.route('/')
def index():
    """主页"""
    config = load_config()
    return render_template('index.html', config=config)

@app.route('/api/save_config', methods=['POST'])
def save_settings():
    """保存设置"""
    try:
        config = request.json
        save_config(config)
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route('/api/start_trading', methods=['POST'])
def start_trading():
    """启动交易"""
    global global_trader, trader_thread
    try:
        if trader_thread and trader_thread.is_alive():
            return jsonify({"status": "error", "message": "Trading already running"})
        
        config = load_config()
        global_trader = BinanceFuturesTrader(config)
        trader_thread = Thread(target=global_trader.run_strategy)
        trader_thread.start()
        return jsonify({"status": "success"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route('/api/stop_trading', methods=['POST'])
def stop_trading():
    """停止交易"""
    global global_trader
    try:
        if global_trader:
            global_trader.stop_trading = True
            return jsonify({"status": "success"})
        return jsonify({"status": "error", "message": "No trading instance running"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route('/api/status')
def get_status():
    """获取交易状态"""
    global global_trader
    try:
        if global_trader:
            position = global_trader.get_position()
            return jsonify({
                "status": "running" if trader_thread and trader_thread.is_alive() else "stopped",
                "position": position,
                "last_error": global_trader.last_error
            })
        return jsonify({"status": "not_initialized"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
