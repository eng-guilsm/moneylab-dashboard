// data is loaded from data.js into rawData variable
let chartInstance = null;

function loadData() {
    initChart();
}

function initChart() {
    const ctx = document.getElementById('priceChart').getContext('2d');
    
    chartInstance = new Chart(ctx, {
        type: 'line',
        data: {
            labels: rawData.timestamps,
            datasets: [
                {
                    label: 'USD/BRL',
                    data: rawData.prices,
                    borderColor: '#2196F3',
                    borderWidth: 2,
                    pointRadius: 0,
                    fill: false,
                    tension: 0.1
                },
                {
                    label: 'Upper Risk',
                    data: rawData.upper_risk,
                    borderColor: 'rgba(244, 67, 54, 0.5)',
                    borderWidth: 1,
                    borderDash: [5, 5],
                    pointRadius: 0,
                    fill: false,
                    hidden: false
                },
                {
                    label: 'Lower Risk',
                    data: rawData.lower_risk,
                    borderColor: 'rgba(76, 175, 80, 0.5)',
                    borderWidth: 1,
                    borderDash: [5, 5],
                    pointRadius: 0,
                    fill: false,
                    hidden: false
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
                mode: 'index',
                intersect: false,
            },
            plugins: {
                legend: {
                    labels: { color: '#fff' }
                }
            },
            scales: {
                x: {
                    ticks: { color: '#aaa', maxTicksLimit: 10 }
                },
                y: {
                    ticks: { color: '#aaa' }
                }
            }
        }
    });
}

function runSimulation() {
    if (!rawData) return;
    
    const buyThreshold = parseFloat(document.getElementById('buyThreshold').value) / 100;
    const sellThreshold = parseFloat(document.getElementById('sellThreshold').value) / 100;
    const buyAmountPct = parseFloat(document.getElementById('buyAmountPct').value) / 100;
    const sellAmountPct = parseFloat(document.getElementById('sellAmountPct').value) / 100;
    const avoidRisk = document.getElementById('avoidRisk').checked;
    
    let fiat = 1000.0;
    let crypto = 0.0; // Treating USD as the "asset" we buy
    let trades = 0;
    
    let buyMarkers = [];
    let sellMarkers = [];
    
    let lastTradePrice = rawData.prices[0];
    
    for (let i = 1; i < rawData.prices.length; i++) {
        const price = rawData.prices[i];
        const upRisk = rawData.upper_risk[i];
        const dnRisk = rawData.lower_risk[i];
        
        buyMarkers.push(null);
        sellMarkers.push(null);

        // Skip straight line interpolation regions if any still exist
        if (price === rawData.prices[i-1]) continue;
        
        // Buy Logic
        if (price <= lastTradePrice * (1 - buyThreshold)) {
            // Check risk
            if (avoidRisk && price < dnRisk) {
                continue;
            }
            if (fiat > 0) {
                let tradeAmount = fiat * buyAmountPct;
                if (tradeAmount < 1) tradeAmount = fiat; // Buy all if less than 1
                fiat -= tradeAmount;
                crypto += tradeAmount / price;
                lastTradePrice = price;
                trades++;
                buyMarkers[i] = price;
            }
        }
        
        // Sell Logic
        else if (price >= lastTradePrice * (1 + sellThreshold)) {
            // Check risk
            if (avoidRisk && price > upRisk) {
                continue;
            }
            if (crypto > 0) {
                let tradeCrypto = crypto * sellAmountPct;
                if (tradeCrypto * price < 1) tradeCrypto = crypto; // Sell all if less than $1
                crypto -= tradeCrypto;
                fiat += tradeCrypto * price;
                lastTradePrice = price;
                trades++;
                sellMarkers[i] = price;
            }
        }
    }
    
    const finalValue = fiat + (crypto * rawData.prices[rawData.prices.length - 1]);
    
    document.getElementById('finalCapital').innerText = 'R$ ' + finalValue.toFixed(2);
    document.getElementById('totalTrades').innerText = trades;
    
    updateChartMarkers(buyMarkers, sellMarkers);
}

function updateChartMarkers(buyMarkers, sellMarkers) {
    if (chartInstance.data.datasets.length > 3) {
        chartInstance.data.datasets.splice(3, 2);
    }
    
    chartInstance.data.datasets.push({
        label: 'Buy',
        data: buyMarkers,
        backgroundColor: '#4CAF50',
        borderColor: '#4CAF50',
        pointRadius: 5,
        pointStyle: 'triangle',
        showLine: false
    });
    
    chartInstance.data.datasets.push({
        label: 'Sell',
        data: sellMarkers,
        backgroundColor: '#F44336',
        borderColor: '#F44336',
        pointRadius: 5,
        pointStyle: 'triangle',
        rotation: 180,
        showLine: false
    });
    
    chartInstance.update();
}

document.getElementById('startSimBtn').addEventListener('click', runSimulation);

loadData();
