import { Link } from "wouter";
import { FileQuestion } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function NotFound() {
  return (
    <div className="min-h-[60vh] flex flex-col items-center justify-center text-center px-4">
      <div className="w-16 h-16 bg-muted/50 rounded-full flex items-center justify-center mb-6">
        <FileQuestion className="h-8 w-8 text-muted-foreground" />
      </div>
      <h1 className="text-4xl font-display font-bold tracking-tight mb-2">404</h1>
      <h2 className="text-xl text-foreground font-medium mb-4">Page Not Found</h2>
      <p className="text-muted-foreground max-w-md mb-8">
        The page you're looking for doesn't exist or has been moved. Check the URL and try again.
      </p>
      <div className="flex gap-4">
        <Button asChild>
          <Link href="/">Back to Home</Link>
        </Button>
        <Button variant="outline" asChild>
          <Link href="/blocks">View Blocks</Link>
        </Button>
      </div>
    </div>
  );
}
