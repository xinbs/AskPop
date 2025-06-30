// #popclip extension
// name: AskPop Rewrite Assistant
// language: javascript
// module: true
// entitlements: [network]
// options: [{
//   identifier: apikey,
//   label: API Key,
//   type: string,
//   description: '从 https://platform.openai.com 获取 API key'
// }, {
//   identifier: baseurl,
//   label: API Base URL,
//   type: string,
//   description: '支持 OpenAI/DeepSeek 等API接口，示例：
// https://api.openai.com/v1/
//  
// https://api.deepseek.com/v1/',
//   default: 'https://api.openai.com/v1/'
// }, {
//   identifier: model,
//   label: AI Model,
//   type: string,
//   description: '选择使用的 AI 模型，示例：
// OpenAI: gpt-3.5-turbo, gpt-4
//  
// DeepSeek: deepseek-chat, deepseek-coder',
//   default: 'gpt-3.5-turbo'
// }]

"use strict";

const axios = require("axios");

function createClient(options) {
    return axios.create({
        baseURL: options.baseurl || "https://api.openai.com/v1/"
    });
}

async function callAPI(temperature, input, options, contentPrefix) {
    const openai = createClient(options);
    const model = options.model || "gpt-3.5-turbo";
    
    openai.defaults.headers.common.Authorization = `Bearer ${options.apikey}`;
    const content = `${contentPrefix}\n\n${input.text.trim()}`;
    const messages = [{ "role": "user", "content": content }];
    const { data } = await openai.post("chat/completions", {
        model: model,
        temperature: temperature,
        messages
    });
    return data.choices[0].message.content.trim();
}

const rewrite = {
    title: "改写",
    icon: "symbol:pencil.and.outline",
    after: "preview-result",
    code: async (input, options) => {
        try {
            const response = await callAPI(
                0.2,
                input,
                options,
                "请用专业的语气重写以下文本，保持原文语言不变："
            );
            popclip.pasteText(response);
            popclip.showText(`${response}\n(已复制)`);
            return response;
        } catch (error) {
            console.error('改写功能出错:', error);
            popclip.showText('错误: ' + error.message);
            throw error;
        }
    }
};

const grammar = {
    title: "语法检查",
    icon: "symbol:checkmark.bubble",
    after: "preview-result",
    code: async (input, options) => {
        try {
            const response = await callAPI(
                0,
                input,
                options,
                "你现在是一位专业的英语语法专家。1.检查以下文本是否是英文文本，如果不是，请翻译成英文,直接返回翻译后的文本。2.请如果以下是文本英文，则检查是否有语法错误或者是单词拼写错误。如果有错误，请直接返回修正后的文本；如果没有错误，请直接返回原文。不需要解释。待检查内容是："
            );
            popclip.pasteText(response);
            popclip.showText(`${response}\n(已复制)`);
            return response;
        } catch (error) {
            console.error('语法检查功能出错:', error);
            popclip.showText('错误: ' + error.message);
            throw error;
        }
    }
};

exports.actions = [rewrite, grammar];