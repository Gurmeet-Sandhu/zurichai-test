exports.handler = async (event) => {
    console.log('Hello from Lambda! Event:', JSON.stringify(event, null, 2));
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Hello World from Lambda!',
            timestamp: new Date().toISOString()
        }),
    };
};