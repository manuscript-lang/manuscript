export async function GET(request, {params}) {return Response.json({message: `Hello, ${(await params).name}`});}
