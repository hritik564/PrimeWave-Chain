import * as React from "react"
import { QrCode } from "lucide-react"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"

interface QRModalProps {
  value: string;
  title?: string;
}

export function QRModal({ value, title = "QR Code" }: QRModalProps) {
  // A simple pseudo-QR using a blocky pattern for visualization since we can't easily import a QR lib
  // In a real app we'd use qrcode.react
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="ghost" size="icon" className="h-6 w-6 text-muted-foreground hover:text-foreground">
          <QrCode className="h-3 w-3" />
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
        </DialogHeader>
        <div className="flex flex-col items-center justify-center p-6 space-y-4">
          <div className="bg-white p-4 rounded-xl shadow-sm border">
            {/* Mock QR Code Pattern */}
            <div className="grid grid-cols-5 grid-rows-5 gap-1 w-48 h-48 bg-white p-2">
              {Array.from({ length: 25 }).map((_, i) => (
                <div key={i} className={`w-full h-full ${Math.random() > 0.4 ? 'bg-black' : 'bg-transparent'}`} />
              ))}
            </div>
          </div>
          <p className="font-mono text-xs break-all text-center text-muted-foreground mt-4 max-w-full">
            {value}
          </p>
        </div>
      </DialogContent>
    </Dialog>
  )
}
