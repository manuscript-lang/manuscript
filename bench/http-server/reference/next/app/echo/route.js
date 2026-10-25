export async function POST(request) {
  try {
    const reader=request.body.getReader(); let size=0; const chunks=[];
    while (true) {const {done,value}=await reader.read(); if(done)break; size+=value.length; if(size>4096){await reader.cancel();throw Error('limit');} chunks.push(value);}
    const input=JSON.parse(Buffer.concat(chunks));
    if(typeof input.name!=='string'||Object.keys(input).length!==1)throw Error('shape');
    return Response.json({message:`Hello, ${input.name}`});
  } catch {return new Response('Invalid JSON',{status:400});}
}
