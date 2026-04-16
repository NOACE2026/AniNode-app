const fs = require('fs');
const https = require('https');

function fetch(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(data));
        }).on('error', reject);
    });
}

async function scrape() {
    console.log("Fetching allmanga.to...");
    const html = await fetch('https://allmanga.to/');
    
    const scriptRegex = /src="(\/_next\/static\/chunks\/[^"]+\.js)"/g;
    let match;
    const scripts = [];
    while ((match = scriptRegex.exec(html)) !== null) {
        scripts.push('https://allmanga.to' + match[1]);
    }
    
    console.log(`Found ${scripts.length} JS chunk files. Scanning...`);
    
    for (let script of scripts) {
        try {
            const js = await fetch(script);
            // Look for AES, tobeparsed, or decrypt keywords
            if (js.includes('tobeparsed') || js.includes('AES') || js.includes('decrypt')) {
                console.log(`\nFound keywords in: ${script}`);
                
                // Print a small window around the keyword
                const keywords = ['tobeparsed', 'AES.decrypt', 'parse('];
                for (let kw of keywords) {
                    let idx = js.indexOf(kw);
                    if (idx !== -1) {
                        console.log(`Keyword match for ${kw}:`);
                        console.log(js.substring(Math.max(0, idx - 100), Math.min(js.length, idx + 150)));
                        console.log('-----');
                    }
                }
            }
        } catch(e) {
            console.log(`Error fetching ${script}: ${e.message}`);
        }
    }
    console.log("Done scanning.");
}

scrape();
