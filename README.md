# UIImageToVideo
This is a single class file that make it posible to create videos from UIImages written in Swift 2.

The base code comes from (Thank):
  https://github.com/justinlevi/imagesToVideo/tree/master
and
  http://stackoverflow.com/questions/7645454

Uses:
			let video = VideoFromImages(
				filename: "GravityGame.mov",
				size: CGSizeMake(320, 568),
				success: { (url) -> Void in
				  //Will run when video.finish() is called
					print("SUCCESS: Saved in local file  \(url)")
					print("SUCCESS: Video added to Photos Library")
				},
				failure: { (error) -> Void in
					print(error)
				}
			)
			video.start()
			// add any number of images like this: 
			//(You can also do this in a runnong animation, but it will make the animation slack)
			video.addImage(<UIImage>)
			video.finish()
