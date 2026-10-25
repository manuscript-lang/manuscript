export async function GET() {
  const encoder=new TextEncoder(); let timer;
  const stream=new ReadableStream({start(controller){controller.enqueue(encoder.encode('data: one\n\n'));timer=setTimeout(()=>{controller.enqueue(encoder.encode('data: two\n\n'));controller.close();},10);},cancel(){clearTimeout(timer);}});
  return new Response(stream,{headers:{'Content-Type':'text/event-stream'}});
}
